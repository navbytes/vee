import XCTest
@testable import VeeApp
import VeeCore
import VeeCatalog
import VeePreferences

/// Covers the disk-authoritative reconciliation GC in `AppController.reload()`
/// (`reconcileDiskState`): every piece of per-plugin state — the disabled
/// flag, hotkey prefs, `.vars.json`, the Keychain secret, catalog provenance —
/// is keyed by filename, so a stale record must be cleared the moment its
/// file genuinely disappears, whether that happened through the app's own
/// delete button or a manual Finder/`rm` delete outside it entirely.
///
/// Every fixture declares `<vee.surface>widget</vee.surface>` so its
/// `PluginCoordinator` never builds an `NSStatusItem` — the same construction
/// `PluginCoordinatorRefreshOverlapTests`/`WidgetActionRefreshTests` use to
/// never touch `NSApplication.shared` (a CI-flake: it rebinds the MainActor
/// executor process-wide). `AppPreferences.shared`/`UserDefaults.standard` is
/// used directly (no injection seam on `AppController` for it) — every
/// filename here is UUID-suffixed so tests can never collide with each other
/// or with residue from a previous run; each test's own assertions are the
/// cleanup (they prove the state is gone).
@MainActor
final class PluginLifecycleReconciliationTests: XCTestCase {
    private func tempDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-reconcile-\(UUID().uuidString)", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writePlugin(named name: String, in dir: String) -> String {
        let path = (dir as NSString).appendingPathComponent(name)
        let source = "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho hi\n"
        try? source.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// Tears down every scheduled timer/task a real `reload()` may have
    /// started, so a leaked widget-cadence scheduler can't outlive the test
    /// into the rest of the process's test run. Safe to call without a live
    /// `NSApplication` — `applicationWillTerminate` never touches `NSApp`.
    private func cleanup(_ controller: AppController) {
        controller.applicationWillTerminate(Notification(name: Notification.Name("test-cleanup")))
    }

    // MARK: - Fix 1: manual delete + reload() GCs every satellite store

    func testManualDeleteThenReloadGCsDisabledVarsSecretAndProvenance() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        let filename = "clock-\(UUID().uuidString).5s.sh"
        let path = writePlugin(named: filename, in: dir)

        let secrets = InMemorySecretStore()
        let controller = AppController(secretStoreFactory: { _ in secrets })
        defer { cleanup(controller) }

        controller.reload()
        XCTAssertTrue(controller.isLoaded(id: filename), "sanity: the plugin loaded before any of this")

        // Establish state across every satellite store, all keyed by filename.
        AppPreferences.shared.setDisabled(true, id: filename)
        AppPreferences.shared.setHotkeyDisabled(true, id: filename)
        AppPreferences.shared.setHotkeyBinding("cmd+shift+j", id: filename)
        try VarStore(pluginPath: path).set("dark", for: "THEME")
        secrets.set("s3cret", for: "API_TOKEN")
        let provenanceStore = ProvenanceStore(directory: dir)
        try provenanceStore.record(
            PluginProvenance(filename: filename, sourceURL: URL(string: "https://example.com/\(filename)")!, source: "x")
        )

        // A MANUAL delete — not `deletePlugin()` — Finder/`rm`, bypassing the
        // app entirely. The directory watcher fires `reload()` on any change,
        // in-app delete or not, so this is the scenario that actually matters.
        try FileManager.default.removeItem(atPath: path)

        controller.reload()

        XCTAssertFalse(AppPreferences.shared.isDisabled(filename), "the disabled flag must be GC'd")
        XCTAssertFalse(AppPreferences.shared.isHotkeyDisabled(filename), "the hotkey-off flag must be GC'd")
        XCTAssertNil(AppPreferences.shared.hotkeyBinding(filename), "the custom hotkey binding must be GC'd")
        XCTAssertTrue(VarStore(pluginPath: path).load().isEmpty, "the .vars.json sidecar must be GC'd")
        XCTAssertNil(secrets.get("API_TOKEN"), "the Keychain secret must be GC'd — irreversible, but this filename is genuinely gone")
        XCTAssertNil(provenanceStore.record(for: filename), "the provenance record must be GC'd")
    }

    /// The hard guard: a directory that can't even be listed (permissions,
    /// an unmounted volume, …) must never be treated as "everything's gone".
    /// `PluginDiscovery.enumerate`'s `try?` folds that failure into an empty
    /// array — indistinguishable from a genuinely empty folder — so this
    /// proves `reload()` does NOT fall for that: it must take its own
    /// raw listing and bail out entirely on a real failure.
    func testReloadDoesNotGCWhenDirectoryEnumerationFails() {
        // Constructed but never created — `contentsOfDirectory` throws.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-reconcile-missing-\(UUID().uuidString)", isDirectory: true).path
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir), "sanity: the directory really doesn't exist")

        let filename = "ghost-\(UUID().uuidString).5s.sh"
        AppPreferences.shared.setDisabled(true, id: filename)
        defer { AppPreferences.shared.setDisabled(false, id: filename) }

        let controller = AppController(secretStoreFactory: { _ in InMemorySecretStore() })
        defer { cleanup(controller) }

        controller.reload()

        XCTAssertTrue(AppPreferences.shared.isDisabled(filename), "a failed/unreadable directory listing must never GC state — it could be a transient failure, not genuine absence")
    }

    // MARK: - Fix 2: reinstalling under the same filename doesn't inherit the old disabled flag

    func testDisableThenManualDeleteThenReinstallSameFilenameIsEnabledAndLoaded() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        // A permanent sibling keeps the directory non-empty throughout, so
        // the manual delete below stays a genuine "one plugin gone, the
        // folder isn't untouched" case — not the pathological fully-empty
        // directory the empty-listing guard (fix 1, review round) deliberately
        // refuses to GC against (an unmounted volume looks identical).
        writePlugin(named: "sibling-\(UUID().uuidString).sh", in: dir)

        let filename = "clock-\(UUID().uuidString).5s.sh"
        let path = (dir as NSString).appendingPathComponent(filename)

        let controller = AppController(secretStoreFactory: { _ in InMemorySecretStore() })
        defer { cleanup(controller) }

        writePlugin(named: filename, in: dir)
        controller.reload()
        XCTAssertTrue(controller.isLoaded(id: filename), "sanity: loads once installed")

        AppPreferences.shared.setDisabled(true, id: filename)
        controller.reload()
        XCTAssertFalse(controller.isLoaded(id: filename), "disabled — must not be loaded")

        try? FileManager.default.removeItem(atPath: path) // manual delete while disabled
        controller.reload() // GC clears the now-stale disabled flag

        writePlugin(named: filename, in: dir) // reinstall under the SAME filename
        controller.reload()

        XCTAssertFalse(AppPreferences.shared.isDisabled(filename), "a reinstall under the same filename must not inherit the old disabled flag")
        XCTAssertTrue(controller.isLoaded(id: filename), "the reinstalled plugin must be enabled and loaded, not silently filtered out by enabledPlugins()")
    }

    // MARK: - BLOCKING review fix: a successful but EMPTY listing must never GC

    /// A successful listing that's simply EMPTY is a DIFFERENT failure shape
    /// than a throw, and must be guarded separately — it's exactly what a
    /// plugins directory on a not-yet-mounted network/automount volume looks
    /// like: `PluginsDirectory.ensureExists` `mkdir`s an empty LOCAL
    /// placeholder an instant before the real volume mounts over it, and
    /// `UserDefaults`-backed candidates (`disabledIDs()`) are readable
    /// regardless of whether the real directory has mounted yet. Without this
    /// guard, that split-second window wipes every plugin's disabled flag
    /// and Keychain secret; the plugins then silently reappear re-enabled
    /// once the mount lands, tokens gone — unrecoverable. Fails before the
    /// `!onDisk.isEmpty` guard, passes after.
    func testReloadDoesNotGCOnASuccessfulButEmptyListing() {
        let dir = tempDir() // mkdir'd, but nothing ever written into it
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: dir), [], "sanity: a real, successful listing — empty, not a throw")

        let filename = "ghost-\(UUID().uuidString).5s.sh"
        AppPreferences.shared.setDisabled(true, id: filename)
        defer { AppPreferences.shared.setDisabled(false, id: filename) }
        let secrets = InMemorySecretStore()
        secrets.set("s3cret", for: "API_TOKEN")

        let controller = AppController(secretStoreFactory: { _ in secrets })
        defer { cleanup(controller) }

        controller.reload()

        XCTAssertTrue(AppPreferences.shared.isDisabled(filename), "an empty-but-successful listing must not be treated as genuine absence")
        XCTAssertNotNil(secrets.get("API_TOKEN"), "the Keychain secret must survive an empty-listing reload — deleting it is irreversible")
    }

    // MARK: - Atomic in-place update never appears absent to reconcile

    func testInPlaceUpdateNeverAppearsAbsentToReconcile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        let filename = "clock-\(UUID().uuidString).5s.sh"
        let path = writePlugin(named: filename, in: dir)

        let secrets = InMemorySecretStore()
        let controller = AppController(secretStoreFactory: { _ in secrets })
        defer { cleanup(controller) }
        controller.reload()

        AppPreferences.shared.setDisabled(true, id: filename)
        defer { AppPreferences.shared.setDisabled(false, id: filename) }
        secrets.set("s3cret", for: "API_TOKEN")

        // An in-place UPDATE — `PluginInstaller.install` again under the
        // same filename, the exact atomic temp+rename primitive Discover's
        // Update button uses; it never removes `path` first.
        try PluginInstaller.install(filename: filename, source: "#!/bin/bash\n# <vee.surface>widget</vee.surface>\necho updated\n", into: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "sanity: atomic replace never leaves the destination momentarily missing")

        controller.reload()

        XCTAssertTrue(AppPreferences.shared.isDisabled(filename), "an atomic in-place update must never look like a delete to reconcile")
        XCTAssertNotNil(secrets.get("API_TOKEN"))
    }

    // MARK: - Fix 1(d): a secret-only plugin (no other state) is still found

    /// A plugin with a stored secret but no disabled flag, vars, or
    /// provenance record used to be invisible to `reconcileDiskState`'s
    /// candidate set entirely — closed by `AppPreferences.secretPluginIDs()`,
    /// the marker `PluginPreferences.setValue` records (see
    /// `VeePreferencesTests` for that write-side test). This proves the
    /// GC/consume side directly, without needing `VarDeclaration` (a
    /// `VeePluginFormat` type this test target doesn't depend on).
    func testSecretOnlyPluginIsStillGCdOnDelete() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        setenv("VEE_PLUGINS_DIR", dir, 1)
        defer { unsetenv("VEE_PLUGINS_DIR") }

        let filename = "secret-only-\(UUID().uuidString).sh"
        let path = writePlugin(named: filename, in: dir)
        // A sibling keeps the directory non-empty after the target is
        // deleted — isolates this test to the marker fix, not the separate
        // empty-listing guard above.
        writePlugin(named: "sibling-\(UUID().uuidString).sh", in: dir)

        let secrets = InMemorySecretStore()
        let controller = AppController(secretStoreFactory: { _ in secrets })
        defer { cleanup(controller) }
        controller.reload()

        // No disabled flag, no vars, no provenance — a secret is the ONLY
        // state, recorded the same way `PluginPreferences.setValue` does.
        secrets.set("s3cret", for: "API_TOKEN")
        AppPreferences.shared.setHasSecret(true, id: filename)

        try? FileManager.default.removeItem(atPath: path)
        controller.reload()

        XCTAssertNil(secrets.get("API_TOKEN"), "a secret-only plugin must still be GC'd once genuinely absent")
        XCTAssertFalse(AppPreferences.shared.secretPluginIDs().contains(filename), "the marker itself must be cleared too")
    }
}
