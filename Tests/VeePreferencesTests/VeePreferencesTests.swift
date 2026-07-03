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

final class PluginPreferencesTests: XCTestCase {
    private func decls() -> [VarDeclaration] {
        [
            VarDeclaration(name: "API_TOKEN", kind: .string, defaultValue: "", summary: "", options: [], isSecret: true),
            VarDeclaration(name: "COUNT", kind: .number, defaultValue: "10", summary: "", options: [], isSecret: false),
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
