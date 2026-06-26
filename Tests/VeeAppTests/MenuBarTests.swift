import XCTest
@testable import VeeApp
import VeeProtocol

/// Menu-bar command surfacing: the render-tree → status-item projection, the
/// `MenuBarController` (per-plugin mirror → present + click → invokeAction), and
/// the `AppCoordinator` demux that routes menu-bar frames off the launcher surface.
final class MenuBarTests: XCTestCase {

    private func renderNote(pluginId: String, revision: Int,
                            patch: JSONPatchDocument) throws -> JSONRPCMessage {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(params))
        return .notification(JSONRPCNotification(method: RPCMethods.render, params: value))
    }

    // MARK: - Projection

    func testProjectionExtractsTitleIconItemsAndSeparator() {
        let tree = RenderNode(tag: "root",
            props: ["title": .string("●3"), "icon": .string("circle.fill")],
            children: [
                RenderNode(tag: "list", children: [
                    RenderNode(tag: RenderNode.Tag.listItem,
                               props: ["title": .string("Alpha"), "subtitle": .string("streaming"),
                                       "actionId": .string("focus:a")]),
                    RenderNode(tag: "separator"),
                    RenderNode(tag: RenderNode.Tag.listItem,
                               props: ["title": .string("Refresh"), "actionId": .string("refresh")]),
                ]),
            ])
        let p = ViewModelProjector.menuBar(from: tree)
        XCTAssertEqual(p.title, "●3")
        XCTAssertEqual(p.icon, "circle.fill")
        XCTAssertEqual(p.items.count, 3)
        XCTAssertEqual(p.items[0].actionId, "focus:a")
        XCTAssertEqual(p.items[0].subtitle, "streaming")
        XCTAssertTrue(p.items[1].isSeparator)
        XCTAssertEqual(p.items[2].title, "Refresh")
        XCTAssertFalse(p.items[2].isSeparator)
    }

    func testProjectionPullsActionIdFromNestedActionPanel() {
        // A list-item with no `actionId` prop but a primary action in an action-panel.
        let tree = RenderNode(tag: "root", children: [
            RenderNode(tag: RenderNode.Tag.listItem, props: ["title": .string("Open PR")], children: [
                RenderNode(tag: RenderNode.Tag.actionPanel, children: [
                    RenderNode(tag: RenderNode.Tag.action,
                               props: ["actionId": .string("open:42"), "title": .string("Open")]),
                ]),
            ]),
        ])
        XCTAssertEqual(ViewModelProjector.menuBar(from: tree).items.first?.actionId, "open:42")
    }

    // MARK: - Controller

    func testControllerProjectsRenderToPresenterAndClickFiresInvokeAction() throws {
        let presenter = FakePluginMenuBar()
        let transport = TestPeerTransport()
        let controller = MenuBarController(presenter: presenter, transport: transport)
        controller.register(pluginId: "com.vee.mb")

        let tree = RenderNode(tag: "root", props: ["title": .string("●2")], children: [
            RenderNode(tag: "list", children: [
                RenderNode(tag: RenderNode.Tag.listItem,
                           props: ["title": .string("Item A"), "actionId": .string("a")]),
            ]),
        ])
        controller.handleFrame(try renderNote(pluginId: "com.vee.mb", revision: 1,
                                              patch: [.replace("", tree.jsonValue)]))

        XCTAssertEqual(presenter.lastTitle, "●2")
        XCTAssertEqual(presenter.lastItems.map(\.title), ["Item A"])

        // A dropdown selection → exactly one host.invokeAction toward the plugin.
        presenter.lastOnSelect?("a")
        XCTAssertEqual(transport.sent.count, 1)
        guard case .notification(let note) = transport.sent[0], let params = note.params else {
            return XCTFail("expected an invokeAction notification")
        }
        XCTAssertEqual(note.method, RPCMethods.invokeAction)
        let p = try JSONDecoder().decode(InvokeActionParams.self, from: JSONEncoder().encode(params))
        XCTAssertEqual(p.pluginId, "com.vee.mb")
        XCTAssertEqual(p.actionId, "a")
    }

    func testControllerIgnoresFramesForUnregisteredPlugin() throws {
        let presenter = FakePluginMenuBar()
        let controller = MenuBarController(presenter: presenter, transport: TestPeerTransport())
        // NOT registered.
        controller.handleFrame(try renderNote(pluginId: "com.vee.unknown", revision: 1,
                                              patch: [.replace("", RenderNode(tag: "root").jsonValue)]))
        XCTAssertNil(presenter.lastTitle)
        XCTAssertTrue(presenter.lastItems.isEmpty)
    }

    func testControllerDropsStaleRevision() throws {
        let presenter = FakePluginMenuBar()
        let controller = MenuBarController(presenter: presenter, transport: TestPeerTransport())
        controller.register(pluginId: "com.vee.mb")

        let t1 = RenderNode(tag: "root", props: ["title": .string("first")], children: [])
        controller.handleFrame(try renderNote(pluginId: "com.vee.mb", revision: 2,
                                              patch: [.replace("", t1.jsonValue)]))
        XCTAssertEqual(presenter.lastTitle, "first")

        // Revision 1 < 2 → dropped; presenter still shows the revision-2 render.
        let t2 = RenderNode(tag: "root", props: ["title": .string("stale")], children: [])
        controller.handleFrame(try renderNote(pluginId: "com.vee.mb", revision: 1,
                                              patch: [.replace("", t2.jsonValue)]))
        XCTAssertEqual(presenter.lastTitle, "first")
    }

    // MARK: - Coordinator demux

    func testCoordinatorForwardsMenuBarFramesAndLeavesLauncherSurfaceIntact() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher", transport: transport, host: FakeHost())
        let router = SpyMenuBarRouter()
        coordinator.menuBarRouter = router
        coordinator.registerMenuBarPlugin("com.vee.mb")
        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")],
                                       sectionTitle: "Applications") { _ in }

        // A menu-bar plugin frame is demuxed to the router, NOT the launcher.
        transport.deliverInbound(try renderNote(pluginId: "com.vee.mb", revision: 1,
            patch: [.replace("", RenderNode(tag: "root", props: ["title": .string("x")]).jsonValue)]))
        XCTAssertEqual(router.frames.count, 1)
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["safari"],
                       "the launcher surface must be untouched by a menu-bar frame")
    }
}

private final class FakePluginMenuBar: PluginMenuBarPresenting {
    var lastTitle: String?
    var lastIcon: String?
    var lastItems: [MenuBarItemViewModel] = []
    var lastOnSelect: ((String) -> Void)?
    private(set) var removed: [String] = []
    func upsert(pluginId: String, title: String?, iconSymbol: String?,
                items: [MenuBarItemViewModel], onSelect: @escaping (String) -> Void) {
        lastTitle = title; lastIcon = iconSymbol; lastItems = items; lastOnSelect = onSelect
    }
    func remove(pluginId: String) { removed.append(pluginId) }
}

private final class SpyMenuBarRouter: MenuBarRouting {
    private(set) var frames: [JSONRPCMessage] = []
    func handleFrame(_ message: JSONRPCMessage) { frames.append(message) }
}
