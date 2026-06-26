import XCTest
@testable import VeeEngine
import VeeProtocol

/// Runtime delivery of plugin preferences. The host resolves a command's
/// preference values and injects them so the SDK's `getPreferenceValues()` —
/// which reads `vee.preferences` — and `ctx.preferences` both see them
/// synchronously inside the command body. These tests drive real JavaScriptCore
/// and read the values back through a context-local global (the same technique the
/// engine suite uses elsewhere).
final class PreferencesRuntimeTests: XCTestCase {

    /// A bundle whose `view` command copies the injected preferences into globals,
    /// reading both the `vee.preferences` global (what `getPreferenceValues()`
    /// returns) and the `ctx.preferences` convenience.
    private func bundle() -> String {
        """
        globalThis.__veePref = "(unset)";
        globalThis.__ctxPref = "(unset)";
        globalThis.__veePlugin = {
          commandNames: ["view"],
          activateCommand: function(name, ctx) {
            globalThis.__veePref = (vee.preferences && vee.preferences.token) || "(none)";
            globalThis.__ctxPref = (ctx.preferences && ctx.preferences.token) || "(none)";
            ctx.render({ tag: "root", props: {}, children: [] });
          }
        };
        """
    }

    private func manifest(_ id: String = "com.vee.pref") -> PluginManifest {
        PluginManifest(id: id, name: id, version: "1", entrypoint: "x",
                       commands: [PluginCommand(name: "view", title: "View", mode: .view)])
    }

    private func makeHost() -> PluginHost {
        PluginHost(transport: LoopbackTransport(), clock: DispatchClock(),
                   httpClient: CannedHTTPClient(), bundler: StaticBundler(source: ""))
    }

    func testInjectedPreferencesReachVeeGlobalAndContext() throws {
        let host = makeHost()
        _ = try host.load(manifest: manifest(), source: bundle())
        try host.activate(ActivateParams(pluginId: "com.vee.pref", commandName: "view",
                                         preferences: ["token": .string("secret-abc")]))
        host.instance(for: "com.vee.pref")?.runUntilQuiescent()

        XCTAssertEqual(host.instance(for: "com.vee.pref")?.evaluate("globalThis.__veePref")?.toString(),
                       "secret-abc", "vee.preferences.token must be the injected value")
        XCTAssertEqual(host.instance(for: "com.vee.pref")?.evaluate("globalThis.__ctxPref")?.toString(),
                       "secret-abc", "ctx.preferences.token must be the injected value")
    }

    func testPreferencesGlobalSeededEmptyBeforeActivate() throws {
        let host = makeHost()
        _ = try host.load(manifest: manifest(), source: bundle())
        // Seeded at injection time, so `getPreferenceValues()` is safe pre-activate.
        XCTAssertEqual(host.instance(for: "com.vee.pref")?.evaluate("typeof vee.preferences")?.toString(),
                       "object")
    }

    func testActivateWithoutPreferencesYieldsEmpty() throws {
        let host = makeHost()
        _ = try host.load(manifest: manifest(), source: bundle())
        try host.activate(ActivateParams(pluginId: "com.vee.pref", commandName: "view"))
        host.instance(for: "com.vee.pref")?.runUntilQuiescent()
        // No declared/stored prefs ⇒ token absent ⇒ the bundle's "(none)" fallback.
        XCTAssertEqual(host.instance(for: "com.vee.pref")?.evaluate("globalThis.__veePref")?.toString(),
                       "(none)")
    }
}
