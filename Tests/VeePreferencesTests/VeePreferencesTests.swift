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
}
