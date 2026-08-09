import XCTest
import VeeCore
import VeePluginFormat
@testable import VeePreferences

final class VarStoreTests: XCTestCase {
    private func tempPlugin() -> String {
        NSTemporaryDirectory() + "vee-var-" + UUID().uuidString + ".sh"
    }

    func testRoundTrip() throws {
        let store = VarStore(pluginPath: tempPlugin())
        defer { try? FileManager.default.removeItem(atPath: store.sidecarPath) }
        XCTAssertTrue(store.load().isEmpty)
        try store.set("dark", for: "THEME")
        try store.set("5", for: "COUNT")
        XCTAssertEqual(store.value(for: "THEME"), "dark")
        XCTAssertEqual(store.value(for: "COUNT"), "5")
        XCTAssertEqual(store.sidecarPath.hasSuffix(".vars.json"), true)
    }

    func testClearValue() throws {
        let store = VarStore(pluginPath: tempPlugin())
        defer { try? FileManager.default.removeItem(atPath: store.sidecarPath) }
        try store.set("x", for: "K")
        try store.set(nil, for: "K")
        XCTAssertNil(store.value(for: "K"))
    }

    /// `delete()` removes the sidecar file itself — the disk-reconciliation
    /// GC's cleanup primitive, distinct from clearing individual values.
    func testDeleteRemovesSidecarFile() throws {
        let store = VarStore(pluginPath: tempPlugin())
        try store.set("dark", for: "THEME")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.sidecarPath))

        store.delete()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarPath))
        XCTAssertTrue(store.load().isEmpty)
    }

    /// A missing sidecar is a safe no-op, not an error — GC calls this
    /// unconditionally for every candidate filename, most of which never had
    /// a sidecar at all.
    func testDeleteOnMissingSidecarIsNoOp() {
        let store = VarStore(pluginPath: tempPlugin())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarPath))
        store.delete() // must not throw/crash
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: - D9: fail closed on a corrupt sidecar

    /// `set()` must not clobber a sidecar it can't decode — that would
    /// silently drop every other stored variable for the plugin.
    func testSetDoesNotClobberCorruptSidecar() throws {
        let store = VarStore(pluginPath: tempPlugin())
        defer { try? FileManager.default.removeItem(atPath: store.sidecarPath) }
        let corrupt = Data(#"["not", "a", "dict"]"#.utf8)
        try corrupt.write(to: URL(fileURLWithPath: store.sidecarPath))

        XCTAssertThrowsError(try store.set("x", for: "NEW")) {
            XCTAssertEqual($0 as? VarStore.StoreError, .corruptSidecar)
        }

        // Untouched — not overwritten to a single-key `{"NEW":"x"}` doc.
        let onDisk = try XCTUnwrap(FileManager.default.contents(atPath: store.sidecarPath))
        XCTAssertEqual(onDisk, corrupt)
    }

    /// An absent or genuinely empty sidecar is not "corrupt" — `set()` still
    /// works normally (the happy path this fix must not regress).
    func testSetOnMissingOrEmptySidecarStillWorks() throws {
        let missing = VarStore(pluginPath: tempPlugin())
        defer { try? FileManager.default.removeItem(atPath: missing.sidecarPath) }
        try missing.set("v", for: "K")
        XCTAssertEqual(missing.value(for: "K"), "v")

        let empty = VarStore(pluginPath: tempPlugin())
        defer { try? FileManager.default.removeItem(atPath: empty.sidecarPath) }
        FileManager.default.createFile(atPath: empty.sidecarPath, contents: Data())
        try empty.set("v", for: "K")
        XCTAssertEqual(empty.value(for: "K"), "v")
    }
}

final class InMemorySecretStoreTests: XCTestCase {
    func testSetGetDelete() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get("TOKEN"))
        store.set("abc", for: "TOKEN")
        XCTAssertEqual(store.get("TOKEN"), "abc")
        store.set(nil, for: "TOKEN")
        XCTAssertNil(store.get("TOKEN"))
    }

    /// `deleteAll()` clears every account in the namespace at once — a
    /// plugin can declare several secret vars (several accounts), so
    /// clearing one known name during disk-reconciliation GC isn't enough.
    func testDeleteAllClearsEveryAccount() {
        let store = InMemorySecretStore()
        store.set("abc", for: "API_TOKEN")
        store.set("def", for: "PASSWORD")

        store.deleteAll()

        XCTAssertNil(store.get("API_TOKEN"))
        XCTAssertNil(store.get("PASSWORD"))
    }
}

final class AppPreferencesTests: XCTestCase {
    func testDisableEnableRoundTrip() {
        let defaults = UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertFalse(prefs.isDisabled("p1"))
        prefs.setDisabled(true, id: "p1")
        XCTAssertTrue(prefs.isDisabled("p1"))
        XCTAssertEqual(prefs.disabledIDs(), ["p1"])
        prefs.setDisabled(false, id: "p1")
        XCTAssertFalse(prefs.isDisabled("p1"))
    }

    func testFirstRunFlagDefaultsFalseThenPersists() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        XCTAssertFalse(prefs.hasCompletedFirstRun)
        prefs.hasCompletedFirstRun = true
        XCTAssertTrue(prefs.hasCompletedFirstRun)
    }

    func testHotkeyDisabledRoundTrip() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        XCTAssertFalse(prefs.isHotkeyDisabled("p1"))
        prefs.setHotkeyDisabled(true, id: "p1")
        XCTAssertTrue(prefs.isHotkeyDisabled("p1"))
        XCTAssertFalse(prefs.isHotkeyDisabled("p2"))   // isolated per plugin
        prefs.setHotkeyDisabled(false, id: "p1")
        XCTAssertFalse(prefs.isHotkeyDisabled("p1"))
    }

    func testHotkeyCustomBindingRoundTrip() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        XCTAssertNil(prefs.hotkeyBinding("p1"))
        prefs.setHotkeyBinding("cmd+shift+j", id: "p1")
        XCTAssertEqual(prefs.hotkeyBinding("p1"), "cmd+shift+j")
        // Clearing (nil or empty) removes it.
        prefs.setHotkeyBinding(nil, id: "p1")
        XCTAssertNil(prefs.hotkeyBinding("p1"))
        prefs.setHotkeyBinding("", id: "p1")
        XCTAssertNil(prefs.hotkeyBinding("p1"))
    }

    /// The enumerable companions to `isHotkeyDisabled`/`hotkeyBinding` — disk
    /// reconciliation needs the full id sets, not just per-id checks.
    func testHotkeyDisabledAndBindingIDsEnumerateEverySetID() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        XCTAssertEqual(prefs.hotkeyDisabledIDs(), [])
        XCTAssertEqual(prefs.hotkeyBindingIDs(), [])

        prefs.setHotkeyDisabled(true, id: "p1")
        prefs.setHotkeyDisabled(true, id: "p2")
        prefs.setHotkeyBinding("cmd+shift+j", id: "p2")

        XCTAssertEqual(prefs.hotkeyDisabledIDs(), ["p1", "p2"])
        XCTAssertEqual(prefs.hotkeyBindingIDs(), ["p2"])
    }

    /// `clearAllState` wipes every UserDefaults-backed preference for one id
    /// — disabled, hotkey-off, custom binding, and the has-a-secret marker —
    /// and leaves every other plugin's prefs untouched. This is disk
    /// reconciliation's mutator.
    func testClearAllStateClearsEveryFieldForOnlyThatID() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        prefs.setDisabled(true, id: "ghost")
        prefs.setHotkeyDisabled(true, id: "ghost")
        prefs.setHotkeyBinding("cmd+shift+j", id: "ghost")
        prefs.setHasSecret(true, id: "ghost")
        prefs.setDisabled(true, id: "survivor")

        prefs.clearAllState(id: "ghost")

        XCTAssertFalse(prefs.isDisabled("ghost"))
        XCTAssertFalse(prefs.isHotkeyDisabled("ghost"))
        XCTAssertNil(prefs.hotkeyBinding("ghost"))
        XCTAssertFalse(prefs.secretPluginIDs().contains("ghost"))
        XCTAssertTrue(prefs.isDisabled("survivor"), "clearing one id must never touch another's state")
    }

    /// The enumerable has-a-secret marker set — disk reconciliation's only
    /// way to find a "secret-only" plugin (fix 1(d)).
    func testSecretPluginIDsRoundTrip() {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "vee-test-" + UUID().uuidString)!)
        XCTAssertEqual(prefs.secretPluginIDs(), [])

        prefs.setHasSecret(true, id: "p1")
        prefs.setHasSecret(true, id: "p2")
        XCTAssertEqual(prefs.secretPluginIDs(), ["p1", "p2"])

        prefs.setHasSecret(false, id: "p1")
        XCTAssertEqual(prefs.secretPluginIDs(), ["p2"])
    }
}

final class VariableAggregatorTests: XCTestCase {
    /// Injectable reader: maps a plugin id to its declared variables, so the
    /// aggregation is exercised without touching disk.
    private struct FakeReader: VariableDeclarationReading {
        let map: [String: [VarDeclaration]]
        func declarations(for plugin: AggregatablePlugin) -> [VarDeclaration] {
            map[plugin.id.rawValue] ?? []
        }
    }

    private func plugin(_ id: String) -> AggregatablePlugin {
        AggregatablePlugin(id: PluginID(rawValue: id), name: id, path: "/plugins/\(id)")
    }

    private func decl(_ name: String, secret: Bool) -> VarDeclaration {
        VarDeclaration(name: name, kind: .string, defaultValue: "", summary: "", options: [], isSecret: secret)
    }

    func testAggregatesAcrossPlugins() {
        let reader = FakeReader(map: [
            "a.sh": [decl("API_TOKEN", secret: true), decl("COUNT", secret: false)],
            "b.sh": [decl("URL", secret: false)]
        ])
        let groups = VariableAggregator.aggregate(plugins: [plugin("a.sh"), plugin("b.sh")], reader: reader)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].id, "a.sh")
        XCTAssertEqual(groups[0].declarations.map(\.name), ["API_TOKEN", "COUNT"])
        XCTAssertEqual(groups[1].declarations.map(\.name), ["URL"])
    }

    func testOmitsPluginsWithoutVars() {
        let reader = FakeReader(map: ["a.sh": [decl("X", secret: false)], "b.sh": []])
        let groups = VariableAggregator.aggregate(plugins: [plugin("a.sh"), plugin("b.sh")], reader: reader)
        XCTAssertEqual(groups.map(\.id), ["a.sh"])
    }

    func testEmptyWhenNoPlugins() {
        let groups = VariableAggregator.aggregate(plugins: [], reader: FakeReader(map: [:]))
        XCTAssertTrue(groups.isEmpty)
    }

    func testSecretPlainPartition() {
        let reader = FakeReader(map: [
            "a.sh": [decl("API_TOKEN", secret: true), decl("HOST", secret: false), decl("PASSWORD", secret: true)]
        ])
        let groups = VariableAggregator.aggregate(plugins: [plugin("a.sh")], reader: reader)
        XCTAssertEqual(groups[0].secretDeclarations.map(\.name), ["API_TOKEN", "PASSWORD"])
        XCTAssertEqual(groups[0].plainDeclarations.map(\.name), ["HOST"])
    }

    func testPreservesInputOrder() {
        let reader = FakeReader(map: ["z.sh": [decl("A", secret: false)], "a.sh": [decl("B", secret: false)]])
        let groups = VariableAggregator.aggregate(plugins: [plugin("z.sh"), plugin("a.sh")], reader: reader)
        XCTAssertEqual(groups.map(\.id), ["z.sh", "a.sh"])
    }
}

final class PluginPreferencesTests: XCTestCase {
    private func decls() -> [VarDeclaration] {
        [
            VarDeclaration(name: "API_TOKEN", kind: .string, defaultValue: "", summary: "", options: [], isSecret: true),
            VarDeclaration(name: "COUNT", kind: .number, defaultValue: "10", summary: "", options: [], isSecret: false)
        ]
    }

    func testDefaultsWhenUnset() {
        let path = NSTemporaryDirectory() + "vee-pref-" + UUID().uuidString + ".sh"
        defer { try? FileManager.default.removeItem(atPath: path + ".vars.json") }
        let prefs = PluginPreferences(pluginPath: path, pluginID: PluginID(rawValue: "p"), declarations: decls(), secretStore: InMemorySecretStore())
        XCTAssertEqual(prefs.value(for: decls()[0]), "")   // secret default
        XCTAssertEqual(prefs.value(for: decls()[1]), "10") // number default
    }

    func testSecretGoesToKeychainNotSidecar() throws {
        let path = NSTemporaryDirectory() + "vee-pref-" + UUID().uuidString + ".sh"
        defer { try? FileManager.default.removeItem(atPath: path + ".vars.json") }
        defer { AppPreferences.shared.setHasSecret(false, id: "p") }
        let secrets = InMemorySecretStore()
        let prefs = PluginPreferences(pluginPath: path, pluginID: PluginID(rawValue: "p"), declarations: decls(), secretStore: secrets)

        try prefs.setValue("s3cret", for: decls()[0]) // secret
        try prefs.setValue("42", for: decls()[1])     // non-secret

        XCTAssertEqual(secrets.get("API_TOKEN"), "s3cret")
        // The sidecar must NOT contain the secret.
        let sidecar = VarStore(pluginPath: path).load()
        XCTAssertNil(sidecar["API_TOKEN"])
        XCTAssertEqual(sidecar["COUNT"], "42")

        let env = prefs.environmentValues()
        XCTAssertEqual(env["API_TOKEN"], "s3cret")
        XCTAssertEqual(env["COUNT"], "42")
    }

    /// Fix 1(d): storing a secret value must mark the plugin id in
    /// `AppPreferences.secretPluginIDs()` — the only way disk reconciliation
    /// can find a "secret-only" plugin (no disabled flag, vars, or
    /// provenance) whose file has since disappeared. Uses the real
    /// `AppPreferences.shared` (the write path has no injection seam, same
    /// as `PluginCoordinator.registerHotKey`), so the id is UUID-unique and
    /// cleaned up regardless of outcome.
    func testSettingASecretMarksThePluginInAppPreferences() throws {
        let id = "secret-marker-" + UUID().uuidString
        let path = NSTemporaryDirectory() + id + ".sh"
        defer { try? FileManager.default.removeItem(atPath: path + ".vars.json") }
        defer { AppPreferences.shared.setHasSecret(false, id: id) }
        let prefs = PluginPreferences(pluginPath: path, pluginID: PluginID(rawValue: id), declarations: decls(), secretStore: InMemorySecretStore())

        XCTAssertFalse(AppPreferences.shared.secretPluginIDs().contains(id), "sanity: unmarked before any secret is set")

        try prefs.setValue("s3cret", for: decls()[0]) // secret

        XCTAssertTrue(AppPreferences.shared.secretPluginIDs().contains(id))

        // Setting the NON-secret var must never mark it — only a secret does.
        try prefs.setValue("42", for: decls()[1])
        XCTAssertTrue(AppPreferences.shared.secretPluginIDs().contains(id), "still marked — unrelated var write must not unmark it")
    }
}
