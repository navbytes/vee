import XCTest
@testable import VeeApp
import VeeProtocol
import VeeEngine

/// R2-MED-4 regression: until app discovery + the ~5000-app enumeration finished,
/// the cold-open panel showed a blank list with no feedback. The coordinator now
/// has a `.loading` surface (`showLoading()`) that main.swift shows at startup and
/// that the first candidates / render replace. These tests cover the projection,
/// the `isLoading` flag, and that real content clears it.
final class LoadingStateTests: XCTestCase {

    private func renderNote(pluginId: String, revision: Int,
                            patch: JSONPatchDocument) throws -> JSONRPCMessage {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(params))
        return .notification(JSONRPCNotification(method: RPCMethods.render, params: value))
    }

    func testShowLoadingProjectsLoadingSurface() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        coordinator.showLoading()
        XCTAssertTrue(coordinator.isLoading)
        XCTAssertEqual(coordinator.loadingViewModel?.title, "Loading…")
        XCTAssertNil(coordinator.listViewModel)
        XCTAssertNil(coordinator.selectedID, "loading has nothing selectable")
        // ⌘K is a no-op while loading (R2-HIGH-4 interaction).
        XCTAssertTrue(coordinator.actionsForSelection.isEmpty)
    }

    func testShowLoadingPushesLoadingToWindow() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        let window = SpyWindowPresenter()
        coordinator.window = window
        coordinator.showLoading()
        guard case .loading(let vm) = window.lastRoot else {
            return XCTFail("window should receive the .loading root")
        }
        XCTAssertEqual(vm.title, "Loading…")
    }

    func testShowLoadingAcceptsCustomTitle() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        coordinator.showLoading(title: "Finding apps…", description: "One moment")
        XCTAssertEqual(coordinator.loadingViewModel?.title, "Finding apps…")
        XCTAssertEqual(coordinator.loadingViewModel?.description, "One moment")
    }

    /// The first host candidates (apps/commands) replace the loading surface.
    func testHostCandidatesClearLoading() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        coordinator.showLoading()
        XCTAssertTrue(coordinator.isLoading)

        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")],
                                       sectionTitle: "Applications") { _ in }
        XCTAssertFalse(coordinator.isLoading, "candidates must clear the loading state")
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["safari"])
    }

    /// Even an EMPTY candidate set (discovery finished, nothing installed) clears
    /// loading — it resolves to an empty list surface, never a stuck spinner.
    func testEmptyHostCandidatesStillClearLoading() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        coordinator.showLoading()
        coordinator.showHostCandidates([]) { _ in }
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertNotNil(coordinator.listViewModel)
        XCTAssertEqual(coordinator.listViewModel?.items.count, 0)
    }

    /// A plugin render arriving first also clears the loading surface.
    func testPluginRenderClearsLoading() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.showLoading()
        coordinator.activatePlugin("com.vee.test", command: "view")
        XCTAssertTrue(coordinator.isLoading)

        let tree = RenderNode(tag: RenderNode.Tag.root, children: [
            RenderNode(tag: RenderNode.Tag.list, children: [
                RenderNode(tag: RenderNode.Tag.listItem, key: "x",
                           props: ["title": .string("Rendered")])])])
        transport.deliverInbound(try renderNote(pluginId: "com.vee.test", revision: 1,
                                                patch: [.replace("", tree.jsonValue)]))
        XCTAssertFalse(coordinator.isLoading, "a plugin render must clear the loading state")
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.title), ["Rendered"])
    }

    func testLoadingViewModelEquatable() {
        XCTAssertEqual(LoadingViewModel(), LoadingViewModel(title: "Loading…"))
        XCTAssertNotEqual(LoadingViewModel(title: "A"), LoadingViewModel(title: "B"))
        // The RootViewModel case participates in equality too.
        XCTAssertEqual(RootViewModel.loading(LoadingViewModel()),
                       RootViewModel.loading(LoadingViewModel(title: "Loading…")))
    }
}
