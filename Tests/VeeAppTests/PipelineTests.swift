import XCTest
@testable import VeeApp
import VeeProtocol
import VeeEngine

/// ARCH-1 / ARCH-3 regression (docs/AUDIT.md §5). Before the fix the coordinator
/// was hardwired to "com.vee.launcher" and dropped every real plugin's render at
/// the id filter. These tests assert that activating a plugin command retargets
/// the coordinator so the plugin's render reaches the window, that frames for
/// other ids stay filtered, and that `showRoot()` restores the launcher surface.
final class PipelineTests: XCTestCase {

    private func renderNote(pluginId: String, revision: Int,
                            patch: JSONPatchDocument) throws -> JSONRPCMessage {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(params))
        return .notification(JSONRPCNotification(method: RPCMethods.render, params: value))
    }

    func testActivatePluginRetargetsSoPluginRenderReachesWindow() throws {
        let transport = TestPeerTransport()
        let host = FakeHost()
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher", transport: transport, host: host)
        let window = SpyWindowPresenter()
        coordinator.window = window

        // Root: host-native apps under the launcher id.
        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")],
                                       sectionTitle: "Applications") { _ in }
        XCTAssertEqual(coordinator.pluginId, "com.vee.launcher")

        // Activate a plugin command → coordinator retargets + drives the host.
        coordinator.activatePlugin("com.vee.clipboard", command: "view")
        XCTAssertEqual(coordinator.pluginId, "com.vee.clipboard")
        XCTAssertEqual(host.activated.last?.pluginId, "com.vee.clipboard")
        XCTAssertEqual(host.activated.last?.commandName, "view")

        // The plugin renders under its OWN id → must reach the window (ARCH-1).
        let tree = RenderNode(tag: RenderNode.Tag.root, children: [
            RenderNode(tag: RenderNode.Tag.list, children: [
                RenderNode(tag: RenderNode.Tag.listItem, key: "c1",
                           props: ["title": .string("Recent copy")])])])
        transport.deliverInbound(try renderNote(pluginId: "com.vee.clipboard", revision: 1,
                                                patch: [.replace("", tree.jsonValue)]))
        let list = try XCTUnwrap(coordinator.listViewModel,
                                 "plugin render must reach the coordinator after retarget (ARCH-1)")
        XCTAssertEqual(list.items.map(\.title), ["Recent copy"])

        // A frame addressed to a different id stays filtered.
        transport.deliverInbound(try renderNote(pluginId: "com.vee.other", revision: 5,
                                                patch: [.replace("", RenderNode(tag: "root").jsonValue)]))
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Recent copy"])

        // Back to root restores the launcher identity + app list.
        coordinator.showRoot()
        XCTAssertEqual(coordinator.pluginId, "com.vee.launcher")
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["safari"])
    }

    /// ARCH-3: a freshly activated plugin's render sequence restarts at 1, which
    /// must not be dropped as "stale" just because an earlier plugin reached a
    /// higher revision.
    func testActivateResetsRevisionSoNewPluginFirstRenderIsNotStale() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher", transport: transport, host: FakeHost())
        // No window needed: this test asserts on the coordinator's projected
        // `listViewModel`, which is driven directly by the render mirror.

        coordinator.activatePlugin("com.vee.a", command: "view")
        for rev in 1...4 {  // plugin A advances the revision to 4
            let t = RenderNode(tag: "root", children: [RenderNode(tag: "list", children: [
                RenderNode(tag: "list-item", key: "a", props: ["title": .string("A\(rev)")])])])
            transport.deliverInbound(try renderNote(pluginId: "com.vee.a", revision: rev,
                                                    patch: [.replace("", t.jsonValue)]))
        }
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["A4"])

        // Switch to plugin B, whose mirror restarts at revision 1.
        coordinator.activatePlugin("com.vee.b", command: "view")
        let bTree = RenderNode(tag: "root", children: [RenderNode(tag: "list", children: [
            RenderNode(tag: "list-item", key: "b", props: ["title": .string("B1")])])])
        transport.deliverInbound(try renderNote(pluginId: "com.vee.b", revision: 1,
                                                patch: [.replace("", bTree.jsonValue)]))
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["B1"],
                       "plugin B's revision 1 must not be dropped as stale (ARCH-3)")
    }

    /// UX-5: a plugin's `plugin.showToast` frame must be routed to the window seam
    /// (style mapped 1:1) rather than silently dropped.
    func testToastNotificationRoutesToWindowSeam() {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher", transport: transport, host: FakeHost())
        let window = ToastCapturingPresenter()
        coordinator.window = window
        coordinator.activatePlugin("com.vee.github", command: "view")

        // A plugin's showToast frame carries its own id; only the active plugin's
        // toasts are surfaced. Built as a raw object so this doesn't depend on
        // ToastParams' init access.
        let frame: JSONValue = .object([
            "pluginId": .string("com.vee.github"),
            "style": .string("failure"),
            "title": .string("Rate limited"),
            "message": .string("Try again in a minute"),
        ])
        transport.deliverInbound(.notification(JSONRPCNotification(method: RPCMethods.toast, params: frame)))

        XCTAssertEqual(window.toasts.count, 1)
        XCTAssertEqual(window.toasts.first?.style, .failure)
        XCTAssertEqual(window.toasts.first?.title, "Rate limited")
        XCTAssertEqual(window.toasts.first?.message, "Try again in a minute")
    }
}

/// Minimal presenter that records toast calls (the shared `SpyWindowPresenter` is
/// `final` and ignores toasts via the protocol's default no-op).
private final class ToastCapturingPresenter: LauncherWindowPresenting {
    private(set) var toasts: [(style: ToastStyle, title: String, message: String?)] = []
    func setRootViewModel(_ root: RootViewModel?) {}
    func showLauncher() {}
    func hideLauncher() {}
    func presentToast(style: ToastStyle, title: String, message: String?) {
        toasts.append((style, title, message))
    }
}
