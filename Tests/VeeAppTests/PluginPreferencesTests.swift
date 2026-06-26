import XCTest
@testable import VeeApp
import VeeProtocol

/// The native side of the Raycast preferences model: the generic
/// `PluginPreferencesStore` (resolution, gating, secret-vs-plain routing — all
/// driven purely by what a plugin DECLARED) and the `AppCoordinator` "Setup
/// required" gate. No test here names a built-in service; everything flows from a
/// manifest's declared `PluginPreference`s.
final class PluginPreferencesTests: XCTestCase {

    /// A github-shaped manifest: one required `password` pref + a defaulted,
    /// non-required dropdown, plus a command-scoped textfield.
    private func manifest() -> PluginManifest {
        PluginManifest(
            id: "com.vee.gh", name: "GitHub", version: "1", entrypoint: "b.js",
            commands: [PluginCommand(
                name: "view", title: "View", mode: .view,
                preferences: [PluginPreference(name: "limit", type: .textfield, title: "Limit",
                                               default: .string("25"))])],
            capabilities: Capabilities(network: ["api.github.com"]),
            preferences: [
                PluginPreference(name: "token", type: .password, title: "Token", required: true),
                PluginPreference(name: "view", type: .dropdown, title: "View",
                                 default: .string("list"),
                                 data: [PreferenceOption(title: "List", value: "list")]),
            ])
    }

    private func makeStore(_ m: PluginManifest)
        -> (PluginPreferencesStore, InMemoryTokenStore, InMemoryPreferenceStore) {
        let secrets = InMemoryTokenStore()
        let plain = InMemoryPreferenceStore()
        return (PluginPreferencesStore(manifests: [m], secrets: secrets, plain: plain), secrets, plain)
    }

    // MARK: resolution

    func testResolvedValuesUsesDefaultsUntilOverridden() {
        let (store, _, _) = makeStore(manifest())
        // token has no default and is unset ⇒ absent; view + limit fall back to defaults.
        var resolved = store.resolvedValues(pluginId: "com.vee.gh", command: "view")
        XCTAssertNil(resolved["token"])
        XCTAssertEqual(resolved["view"]?.stringValue, "list")
        XCTAssertEqual(resolved["limit"]?.stringValue, "25")

        store.setValue(.string("ghp_x"), pluginId: "com.vee.gh",
                       preference: manifest().preferences[0])   // token
        store.setValue(.string("grid"), pluginId: "com.vee.gh",
                       preference: manifest().preferences[1])   // view
        resolved = store.resolvedValues(pluginId: "com.vee.gh", command: "view")
        XCTAssertEqual(resolved["token"]?.stringValue, "ghp_x")  // stored wins
        XCTAssertEqual(resolved["view"]?.stringValue, "grid")    // stored over default
        XCTAssertEqual(resolved["limit"]?.stringValue, "25")     // still default
    }

    // MARK: secret vs plain routing

    func testPasswordRoutesToKeychainAndOthersToPlainStore() {
        let m = manifest()
        let (store, secrets, plain) = makeStore(m)
        store.setValue(.string("ghp_secret"), pluginId: "com.vee.gh", preference: m.preferences[0]) // password
        store.setValue(.string("grid"), pluginId: "com.vee.gh", preference: m.preferences[1])       // dropdown

        // Secret in the token (Keychain) store; NOT in the plain store.
        XCTAssertEqual(secrets.token(plugin: "com.vee.gh", account: "token"), "ghp_secret")
        XCTAssertNil(plain.value(pluginId: "com.vee.gh", name: "token"))
        // Non-secret in the plain store; NOT in the token store.
        XCTAssertEqual(plain.value(pluginId: "com.vee.gh", name: "view")?.stringValue, "grid")
        XCTAssertNil(secrets.token(plugin: "com.vee.gh", account: "view"))
    }

    func testBlankClearsStoredValue() {
        let m = manifest()
        let (store, secrets, _) = makeStore(m)
        store.setValue(.string("ghp_secret"), pluginId: "com.vee.gh", preference: m.preferences[0])
        XCTAssertTrue(store.hasStoredValue(pluginId: "com.vee.gh", preference: m.preferences[0]))
        store.setValue(nil, pluginId: "com.vee.gh", preference: m.preferences[0])
        XCTAssertFalse(store.hasStoredValue(pluginId: "com.vee.gh", preference: m.preferences[0]))
        XCTAssertNil(secrets.token(plugin: "com.vee.gh", account: "token"))
    }

    // MARK: isConfigured gating

    func testIsConfiguredFalseUntilRequiredPasswordSet() {
        let m = manifest()
        let (store, _, _) = makeStore(m)
        XCTAssertFalse(store.isConfigured(pluginId: "com.vee.gh", command: "view"),
                       "required token is unset ⇒ not configured")
        store.setValue(.string("ghp_x"), pluginId: "com.vee.gh", preference: m.preferences[0])
        XCTAssertTrue(store.isConfigured(pluginId: "com.vee.gh", command: "view"))
    }

    func testWhitespaceOnlySecretIsNotConfigured() {
        let m = manifest()
        let (store, _, _) = makeStore(m)
        store.setValue(.string("   "), pluginId: "com.vee.gh", preference: m.preferences[0])
        XCTAssertFalse(store.isConfigured(pluginId: "com.vee.gh", command: "view"))
    }

    func testRequiredPreferenceWithDefaultIsConfigured() {
        // A required pref that carries a default is satisfied by that default.
        let m = PluginManifest(
            id: "p", name: "P", version: "1", entrypoint: "x",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            preferences: [PluginPreference(name: "region", type: .textfield, title: "Region",
                                           required: true, default: .string("us"))])
        let (store, _, _) = makeStore(m)
        XCTAssertTrue(store.isConfigured(pluginId: "p", command: "view"))
    }

    func testUnknownPluginIsNotBlocked() {
        let (store, _, _) = makeStore(manifest())
        XCTAssertTrue(store.isConfigured(pluginId: "com.vee.unknown", command: "view"))
        XCTAssertEqual(store.resolvedValues(pluginId: "com.vee.unknown", command: "view"), [:])
    }

    // MARK: declared-preferences union

    func testDeclaredPreferencesUnionsExtensionAndCommand() {
        let store = PluginPreferencesStore(manifests: [manifest()],
                                           secrets: InMemoryTokenStore(),
                                           plain: InMemoryPreferenceStore())
        XCTAssertEqual(Set(store.declaredPreferences(forPlugin: "com.vee.gh").map(\.name)),
                       ["token", "view", "limit"])
    }

    // MARK: AppCoordinator "Setup required" gate

    func testActivationGatedWhenNotConfigured() {
        let host = FakeHost()
        let coordinator = AppCoordinator(
            pluginId: "com.vee.launcher", transport: TestPeerTransport(), host: host,
            preferences: FakePreferences(configured: false),
            onNeedsConfiguration: { [weak self] id, cmd in self?.needsConfig = (id, cmd) })
        coordinator.activatePlugin("com.vee.gh", command: "view")
        // Did NOT activate, did NOT retarget — surfaced configuration instead.
        XCTAssertTrue(host.activated.isEmpty)
        XCTAssertEqual(coordinator.pluginId, "com.vee.launcher")
        XCTAssertEqual(needsConfig?.0, "com.vee.gh")
        XCTAssertEqual(needsConfig?.1, "view")
    }

    func testActivationDeliversResolvedPreferencesWhenConfigured() {
        let host = FakeHost()
        let coordinator = AppCoordinator(
            pluginId: "com.vee.launcher", transport: TestPeerTransport(), host: host,
            preferences: FakePreferences(configured: true, resolved: ["token": .string("ghp_x")]),
            onNeedsConfiguration: { [weak self] id, cmd in self?.needsConfig = (id, cmd) })
        coordinator.activatePlugin("com.vee.gh", command: "view")
        XCTAssertNil(needsConfig, "configured command must not prompt for setup")
        XCTAssertEqual(coordinator.pluginId, "com.vee.gh")
        XCTAssertEqual(host.activated.last?.preferences, ["token": .string("ghp_x")])
    }

    private var needsConfig: (String, String)?
}

/// A scriptable `PluginPreferenceProviding` for the coordinator gate tests.
private final class FakePreferences: PluginPreferenceProviding {
    let configured: Bool
    let resolved: [String: JSONValue]
    init(configured: Bool, resolved: [String: JSONValue] = [:]) {
        self.configured = configured; self.resolved = resolved
    }
    func resolvedValues(pluginId: String, command: String) -> [String: JSONValue] { resolved }
    func isConfigured(pluginId: String, command: String) -> Bool { configured }
}
