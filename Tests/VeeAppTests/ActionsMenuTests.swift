import XCTest
@testable import VeeApp
import VeeProtocol
import VeeEngine

/// R2-HIGH-4 regression: the footer advertises "Actions ⌘K" on every screen, but
/// ⌘K used to do nothing — a polished dead affordance. These tests cover the
/// coordinator-side projection the ⌘K menu reads (`actionsForSelection`) and the
/// routing decision (when the menu should open vs. be a no-op), plus the pure
/// `ActionsMenuView` width sizing. The live popover itself is verified manually
/// (it needs a window server), but its inputs and the open/no-op decision —
/// where the bug lived — are unit-tested here.
final class ActionsMenuTests: XCTestCase {

    // MARK: Builders

    private func renderNote(pluginId: String, revision: Int,
                            patch: JSONPatchDocument) throws -> JSONRPCMessage {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(params))
        return .notification(JSONRPCNotification(method: RPCMethods.render, params: value))
    }

    /// A plugin list tree where each item carries the given actions (actionId,
    /// title, optional shortcut) under an `action-panel`.
    private func listTree(_ items: [(id: String, title: String,
                                     actions: [(id: String, title: String, shortcut: String?)])]) -> RenderNode {
        RenderNode(tag: RenderNode.Tag.root, children: [
            RenderNode(tag: RenderNode.Tag.list, children: items.map { item in
                RenderNode(tag: RenderNode.Tag.listItem, key: item.id,
                           props: ["title": .string(item.title)],
                           children: [
                            RenderNode(tag: RenderNode.Tag.actionPanel, children: item.actions.map { a in
                                var props: [String: JSONValue] = [
                                    "actionId": .string(a.id), "title": .string(a.title)]
                                if let s = a.shortcut { props["shortcut"] = .string(s) }
                                return RenderNode(tag: RenderNode.Tag.action, props: props)
                            })
                           ])
            })
        ])
    }

    // MARK: - actionsForSelection (the ⌘K menu's data source)

    func testNoActionsWhenNoListSurface() {
        let coordinator = AppCoordinator(pluginId: "com.vee.test",
                                         transport: TestPeerTransport(), host: FakeHost())
        // Fresh coordinator → .none surface, no selection.
        XCTAssertTrue(coordinator.actionsForSelection.isEmpty)
        XCTAssertFalse(coordinator.canShowActionsMenu, "⌘K must be a no-op with no surface")
    }

    func testActionsForSelectionReflectsSelectedPluginItem() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.activatePlugin("com.vee.test", command: "view")

        let tree = listTree([
            (id: "a", title: "Item A", actions: [
                (id: "open-a", title: "Open A", shortcut: "cmd+enter"),
                (id: "copy-a", title: "Copy Link", shortcut: "cmd+c")]),
            (id: "b", title: "Item B", actions: [
                (id: "open-b", title: "Open B", shortcut: nil)]),
        ])
        transport.deliverInbound(try renderNote(pluginId: "com.vee.test", revision: 1,
                                                patch: [.replace("", tree.jsonValue)]))

        // First item is selected by reconcileSelection → its two actions show.
        XCTAssertEqual(coordinator.selectedID, "a")
        XCTAssertEqual(coordinator.actionsForSelection.map(\.actionId), ["open-a", "copy-a"])
        XCTAssertEqual(coordinator.actionsForSelection.map(\.title), ["Open A", "Copy Link"])
        XCTAssertEqual(coordinator.actionsForSelection.first?.shortcut, "cmd+enter")
        XCTAssertTrue(coordinator.canShowActionsMenu)

        // Moving the selection re-points the menu at item B's single action.
        coordinator.select(id: "b")
        XCTAssertEqual(coordinator.actionsForSelection.map(\.actionId), ["open-b"])
        XCTAssertNil(coordinator.actionsForSelection.first?.shortcut)
        XCTAssertTrue(coordinator.canShowActionsMenu)
    }

    /// A host-native row with no declared actions still gets a synthesized "Open"
    /// (so the GUI has something to invoke); ⌘K may legitimately show just that —
    /// the rule is "never an EMPTY menu", not "never a single-action menu".
    func testHostCandidateSynthesizedOpenActionIsShown() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")],
                                       sectionTitle: "Applications") { _ in }
        XCTAssertEqual(coordinator.selectedID, "safari")
        XCTAssertEqual(coordinator.actionsForSelection.map(\.title), ["Open"],
                       "a host row with no actions surfaces the synthesized Open action")
        XCTAssertTrue(coordinator.canShowActionsMenu)
    }

    /// A host candidate that DOES declare actions surfaces those (not the synthetic
    /// Open) — so ⌘K offers the real action set.
    func testHostCandidateDeclaredActionsAreShown() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        let candidate = Candidate(id: "note", title: "New Note",
                                  actions: [CandidateAction(id: "new", title: "Create", shortcut: "cmd+n")])
        coordinator.showHostCandidates([candidate]) { _ in }
        XCTAssertEqual(coordinator.actionsForSelection.map(\.actionId), ["new"])
        XCTAssertEqual(coordinator.actionsForSelection.first?.shortcut, "cmd+n")
    }

    func testNoActionsWhenSelectionClearedOnEmptyResults() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(),
                                         host: FakeHost(),
                                         fuzzy: StubFuzzyMatcher(keepIDs: []))
        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")]) { _ in }
        // A query that matches nothing → empty state, no selection → ⌘K no-op.
        coordinator.setQuery("zzz")
        XCTAssertNil(coordinator.selectedID)
        XCTAssertTrue(coordinator.actionsForSelection.isEmpty)
        XCTAssertFalse(coordinator.canShowActionsMenu)
    }

    // MARK: - Routing: invoking a menu action hits invoke(action:targetId:)

    /// Choosing an action in the ⌘K menu invokes it against the SELECTED item, via
    /// the same `invoke(action:)` the footer uses — forwarded as one
    /// `host.invokeAction` carrying the selected target id (plugin mode).
    func testInvokingSelectedActionForwardsToHostWithSelectedTarget() throws {
        let transport = TestPeerTransport()
        let coordinator = AppCoordinator(pluginId: "com.vee.test", transport: transport, host: FakeHost())
        coordinator.activatePlugin("com.vee.test", command: "view")
        let tree = listTree([
            (id: "a", title: "Item A", actions: [(id: "copy-a", title: "Copy", shortcut: "cmd+c")]),
        ])
        transport.deliverInbound(try renderNote(pluginId: "com.vee.test", revision: 1,
                                                patch: [.replace("", tree.jsonValue)]))
        XCTAssertEqual(coordinator.selectedID, "a")

        // The menu invokes the chosen action id; coordinator targets the selection.
        coordinator.invoke(action: "copy-a")

        let invokeFrames = transport.sent.compactMap { msg -> InvokeActionParams? in
            guard case .notification(let n) = msg, n.method == RPCMethods.invokeAction,
                  let params = n.params,
                  let data = try? JSONEncoder().encode(params) else { return nil }
            return try? JSONDecoder().decode(InvokeActionParams.self, from: data)
        }
        XCTAssertEqual(invokeFrames.count, 1)
        XCTAssertEqual(invokeFrames.first?.actionId, "copy-a")
        XCTAssertEqual(invokeFrames.first?.targetId, "a")
        XCTAssertEqual(invokeFrames.first?.pluginId, "com.vee.test")
    }

    /// In host-native mode, invoking the selected row's action launches it locally
    /// (the injected `invoke` closure) rather than crossing IPC.
    func testInvokingHostCandidateActionCallsLocalInvoke() {
        let coordinator = AppCoordinator(pluginId: "com.vee.launcher",
                                         transport: TestPeerTransport(), host: FakeHost())
        var launched: [String] = []
        coordinator.showHostCandidates([Candidate(id: "safari", title: "Safari")]) { c in
            launched.append(c.id)
        }
        // ⌘K menu would show "Open"; invoking it launches the selected candidate.
        let action = try? XCTUnwrap(coordinator.actionsForSelection.first)
        coordinator.invoke(action: action?.actionId ?? "")
        XCTAssertEqual(launched, ["safari"])
    }

    // MARK: - Pure view sizing (no window server needed)

    @MainActor
    func testActionsMenuWidthClampedToRange() {
        // A trivially short title floors at the min width.
        let narrow = ActionsMenuView.preferredWidth(for: [ActionViewModel(actionId: "x", title: "Go")])
        XCTAssertGreaterThanOrEqual(narrow, 220)
        XCTAssertLessThanOrEqual(narrow, 340)

        // A very long title caps at the max width (never blows out the popover).
        let wide = ActionsMenuView.preferredWidth(for: [
            ActionViewModel(actionId: "x",
                            title: String(repeating: "Very long action title ", count: 8),
                            shortcut: "cmd+shift+enter")])
        XCTAssertEqual(wide, 340, accuracy: 0.5)
    }
}
