import XCTest
@testable import VeeEngine
import VeeProtocol

/// ARCH-2 regression (docs/AUDIT.md §5). With several plugins loaded, host→plugin
/// events must reach the ADDRESSED plugin — not only the last-loaded one. Before
/// the fix, `PluginInstance.init` seized the transport's single `onReceive` slot,
/// so each `load()` clobbered the previous instance AND the host's multiplexer;
/// only the last plugin (e.g. the 3rd of 3) ever received `host.invokeAction`.
///
/// Receipt is observed the way the engine suite's canonical invoke test does — by
/// having the handler mutate a per-context JS global, then reading it back via
/// `evaluate`. That keeps the test off the transport's outbound path entirely (no
/// `console.log`/`notify` round-trip), so it exercises only the routing under test.
final class MultiPluginRoutingTests: XCTestCase {

    /// A minimal bundle whose `view` command registers an invokeAction handler
    /// that appends the received actionId to a context-local global.
    private func bundle() -> String {
        """
        globalThis.__got = [];
        globalThis.__veePlugin = {
          commandNames: ["view"],
          activateCommand: function(name, ctx) {
            vee.onInvokeAction(function(p) { globalThis.__got.push(p.actionId); });
            ctx.render({ tag: "root", props: {}, children: [] });
          }
        };
        """
    }

    private func manifest(_ id: String) -> PluginManifest {
        PluginManifest(id: id, name: id, version: "1", entrypoint: "x",
                       commands: [PluginCommand(name: "view", title: "View", mode: .view)])
    }

    func testHostRoutesEventsToAddressedPluginNotJustTheLast() throws {
        let transport = LoopbackTransport()
        let host = PluginHost(transport: transport, clock: DispatchClock(),
                              httpClient: CannedHTTPClient(), bundler: StaticBundler(source: ""))

        let ids = ["com.vee.alpha", "com.vee.beta", "com.vee.gamma"]
        for id in ids {
            _ = try host.load(manifest: manifest(id), source: bundle())
            try host.activate(ActivateParams(pluginId: id, commandName: "view"))
        }

        func invoke(_ id: String, _ action: String) throws {
            let params = InvokeActionParams(pluginId: id, actionId: action)
            let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(params))
            transport.sendFromPeer(.notification(
                JSONRPCNotification(method: RPCMethods.invokeAction, params: value)))
        }
        // The FIRST-loaded plugin is the key case (it was clobbered before the fix).
        try invoke("com.vee.alpha", "a1")
        try invoke("com.vee.gamma", "g1")
        for id in ids { host.instance(for: id)?.runUntilQuiescent() }

        func got(_ id: String) -> String? {
            host.instance(for: id)?.evaluate("(globalThis.__got || []).join(',')")?.toString()
        }
        XCTAssertEqual(got("com.vee.alpha"), "a1",
                       "the first-loaded plugin must still receive its event (ARCH-2)")
        XCTAssertEqual(got("com.vee.gamma"), "g1")
        XCTAssertEqual(got("com.vee.beta"), "",
                       "a plugin must NOT receive events addressed to a different id")
    }
}
