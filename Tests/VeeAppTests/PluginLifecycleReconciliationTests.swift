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
}
