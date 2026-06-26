import XCTest
@testable import VeeProtocol

/// The plugin-declared **preferences** contract (the Raycast configuration model).
/// These lock down decode leniency, backward-compatibility, merge precedence, and
/// the `ActivateParams.preferences` carrier so the host and the JS SDK can never
/// drift on how configuration is declared and delivered.
final class PreferencesContractTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: PluginPreference leniency

    func testPreferenceDecodesWithOnlyRequiredKeys() throws {
        // name/type/title are the only required keys; everything else defaults.
        let pref = try decode(PluginPreference.self, #"{"name":"token","type":"password","title":"Token"}"#)
        XCTAssertEqual(pref.name, "token")
        XCTAssertEqual(pref.type, .password)
        XCTAssertEqual(pref.title, "Token")
        XCTAssertFalse(pref.required)          // defaults to false
        XCTAssertNil(pref.default)
        XCTAssertNil(pref.description)
        XCTAssertEqual(pref.data, [])          // defaults to empty
        XCTAssertTrue(pref.isSecret)           // password ⇒ secret
    }

    func testDropdownPreferenceDecodesOptionsAndDefault() throws {
        let json = #"""
        {"name":"view","type":"dropdown","title":"Default View","default":"list",
         "data":[{"title":"List","value":"list"},{"title":"Grid","value":"grid"}]}
        """#
        let pref = try decode(PluginPreference.self, json)
        XCTAssertEqual(pref.type, .dropdown)
        XCTAssertEqual(pref.default?.stringValue, "list")
        XCTAssertEqual(pref.data, [PreferenceOption(title: "List", value: "list"),
                                   PreferenceOption(title: "Grid", value: "grid")])
        XCTAssertFalse(pref.isSecret)
    }

    func testPreferenceRoundTripsExactly() throws {
        let pref = PluginPreference(name: "site", type: .textfield, title: "Site",
                                    description: "Your host", required: true,
                                    default: .string("example.com"), placeholder: "host")
        let data = try JSONEncoder().encode(pref)
        XCTAssertEqual(try JSONDecoder().decode(PluginPreference.self, from: data), pref)
    }

    // MARK: Manifest-level preferences + back-compat

    func testManifestWithoutPreferencesDecodesToEmpty() throws {
        // A manifest authored before `preferences` existed must still load.
        let json = #"""
        {"id":"com.vee.x","name":"X","version":"1","entrypoint":"b.js",
         "commands":[{"name":"view","title":"View","mode":"view","hotkeyActions":[]}],
         "capabilities":{}}
        """#
        let m = try decode(PluginManifest.self, json)
        XCTAssertEqual(m.preferences, [])
        XCTAssertEqual(m.commands.first?.preferences, [])
    }

    func testManifestDecodesExtensionAndCommandPreferences() throws {
        let json = #"""
        {"id":"com.vee.gh","name":"GitHub","version":"1","entrypoint":"b.js",
         "preferences":[{"name":"token","type":"password","title":"Token","required":true}],
         "commands":[{"name":"view","title":"View","mode":"view","hotkeyActions":[],
           "preferences":[{"name":"limit","type":"textfield","title":"Limit"}]}],
         "capabilities":{"network":["api.github.com"]}}
        """#
        let m = try decode(PluginManifest.self, json)
        XCTAssertEqual(m.preferences.map(\.name), ["token"])
        XCTAssertTrue(m.preferences[0].required)
        XCTAssertEqual(m.commands[0].preferences.map(\.name), ["limit"])
    }

    func testManifestPreferencesRoundTrip() throws {
        let m = PluginManifest(
            id: "com.vee.gh", name: "GitHub", version: "1", entrypoint: "b.js",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities(network: ["api.github.com"]),
            preferences: [PluginPreference(name: "token", type: .password, title: "Token", required: true)])
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(PluginManifest.self, from: data), m)
    }

    // MARK: mergedPreferences precedence

    func testMergedPreferencesCommandOverridesExtensionPreservingOrder() {
        let m = PluginManifest(
            id: "p", name: "P", version: "1", entrypoint: "x",
            commands: [PluginCommand(
                name: "view", title: "View", mode: .view,
                preferences: [PluginPreference(name: "shared", type: .textfield, title: "Command Shared"),
                              PluginPreference(name: "only-cmd", type: .checkbox, title: "Only Cmd")])],
            preferences: [PluginPreference(name: "shared", type: .textfield, title: "Ext Shared"),
                          PluginPreference(name: "only-ext", type: .textfield, title: "Only Ext")])
        let merged = m.mergedPreferences(forCommand: "view")
        XCTAssertEqual(merged.map(\.name), ["shared", "only-ext", "only-cmd"])  // order preserved, command wins
        XCTAssertEqual(merged.first { $0.name == "shared" }?.title, "Command Shared")
    }

    func testMergedPreferencesForUnknownCommandIsExtensionOnly() {
        let m = PluginManifest(
            id: "p", name: "P", version: "1", entrypoint: "x",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            preferences: [PluginPreference(name: "ext", type: .textfield, title: "Ext")])
        XCTAssertEqual(m.mergedPreferences(forCommand: "nope").map(\.name), ["ext"])
    }

    // MARK: ActivateParams carrier

    func testActivateParamsDecodesWithoutPreferences() throws {
        let p = try decode(ActivateParams.self, #"{"pluginId":"p","commandName":"c"}"#)
        XCTAssertEqual(p.preferences, [:])
        XCTAssertEqual(p.arguments, [:])
    }

    func testActivateParamsRoundTripsPreferences() throws {
        let p = ActivateParams(pluginId: "p", commandName: "c",
                               arguments: ["q": .string("x")],
                               preferences: ["token": .string("abc"), "n": .number(3)])
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(ActivateParams.self, from: data), p)
        // Encoded form actually carries the values (not silently dropped).
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil((obj?["preferences"] as? [String: Any])?["token"])
    }
}
