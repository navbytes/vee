import XCTest
@testable import VeeApp
import VeeProtocol
import VeeEngine

/// Wave 3 — the VeeApp TDD suite (build plan §4, VeeApp).
///
/// The `AppCoordinator` is a JSON-RPC transport PEER (the launcher side): it
/// attaches to the inbound peer stream the host writes (`plugin.render`,
/// `plugin.setCandidates`, …), keeps its OWN `JSONValue` render mirror, applies
/// inbound JSON-Patch with `VeeJSONPatch.apply`, reconstructs `RenderNode`,
/// projects view models, and sends host→plugin frames (`host.invokeAction`,
/// `host.onSearchTextChange`, `host.submitForm`) back over the transport. It
/// never round-trips on a keystroke (native fuzzy filter); selection survives
/// list patches by id.
///
/// Five cases:
///   1. First render → list VM (replace "" of root→list→3 keyed items).
///   2. Incremental prop patch preserves selection.
///   3. Reorder (move) preserves selection by id.
///   4. Query → native filter, zero IPC on keystroke (then server-filtering does
///      send exactly one host.onSearchTextChange).
///   5. Action dispatch round-trips one host.invokeAction with the right ids.
final class VeeAppTests: XCTestCase {

    // MARK: - Fixtures / builders

    private let pluginId = "com.vee.test"

    /// Build a `root → list → list-items` render tree. Each item is keyed and
    /// carries a single `<action>` child (actionId/title/shortcut) plus an
    /// `action-panel` wrapper so the projection exercises nested action parsing.
    private func listTree(_ items: [(id: String, title: String, subtitle: String)]) -> RenderNode {
        RenderNode(tag: RenderNode.Tag.root, props: [:], children: [
            RenderNode(tag: RenderNode.Tag.list, props: [:], children: items.map { item in
                RenderNode(
                    tag: RenderNode.Tag.listItem,
                    key: item.id,
                    props: [
                        "title": .string(item.title),
                        "subtitle": .string(item.subtitle),
                        "icon": .string("doc"),
                    ],
                    children: [
                        RenderNode(tag: RenderNode.Tag.actionPanel, props: [:], children: [
                            RenderNode(
                                tag: RenderNode.Tag.action,
                                props: [
                                    "actionId": .string("open-\(item.id)"),
                                    "title": .string("Open \(item.title)"),
                                    "shortcut": .string("cmd+enter"),
                                ],
                                children: []),
                        ]),
                    ])
            }),
        ])
    }

    /// A `plugin.render` notification carrying a JSON-Patch over the wire.
    private func renderNotification(revision: Int, patch: JSONPatchDocument) throws -> JSONRPCNotification {
        let params = RenderParams(pluginId: pluginId, revision: revision, patch: patch)
        return JSONRPCNotification(method: RPCMethods.render, params: try encode(params))
    }

    private func setCandidatesNotification(_ candidates: [Candidate]) throws -> JSONRPCNotification {
        let params = SetCandidatesParams(pluginId: pluginId, candidates: candidates)
        return JSONRPCNotification(method: RPCMethods.setCandidates, params: try encode(params))
    }

    private func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Decode the typed params of every outbound notification with `method`.
    private func outboundParams<T: Decodable>(_ rec: TestPeerTransport, method: String, as: T.Type) -> [T] {
        rec.sent.compactMap { message -> T? in
            guard case .notification(let note) = message, note.method == method, let params = note.params else { return nil }
            let data = try? JSONEncoder().encode(params)
            return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
    }

    /// Build a coordinator wired to a fresh test transport, a fake host, and an
    /// injectable fuzzy stub. Returns all three so tests can drive + assert.
    private func makeCoordinator(
        serverSideFiltering: Bool = false,
        fuzzy: FuzzyMatching = LiveFuzzyMatcher()
    ) -> (AppCoordinator, TestPeerTransport, FakeHost) {
        let transport = TestPeerTransport()
        let host = FakeHost()
        let coordinator = AppCoordinator(
            pluginId: pluginId,
            transport: transport,
            host: host,
            fuzzy: fuzzy,
            serverSideFiltering: serverSideFiltering)
        return (coordinator, transport, host)
    }

    // MARK: - Test 1: first render → list view model

    func testFirstRenderProducesListViewModel() throws {
        let (coordinator, transport, _) = makeCoordinator()

        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "first"),
            (id: "b", title: "Bravo", subtitle: "second"),
            (id: "c", title: "Charlie", subtitle: "third"),
        ])
        // First render is shipped by the host as a single replace "" of the whole tree.
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        let list = try XCTUnwrap(coordinator.listViewModel, "expected a ListViewModel after first render")
        XCTAssertEqual(list.items.count, 3)
        XCTAssertEqual(list.items.map(\.id), ["a", "b", "c"], "ids come from the node `key`")
        XCTAssertEqual(list.items.map(\.title), ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(list.items.map { $0.subtitle ?? "" }, ["first", "second", "third"])
        XCTAssertEqual(list.items[0].icon, "doc")

        // Parsed actions (from the nested action-panel → action).
        let firstActions = list.items[0].actions
        XCTAssertEqual(firstActions.count, 1)
        XCTAssertEqual(firstActions.first?.actionId, "open-a")
        XCTAssertEqual(firstActions.first?.title, "Open Alpha")
        XCTAssertEqual(firstActions.first?.shortcut, "cmd+enter")

        // Default selection lands on the first item.
        XCTAssertEqual(coordinator.selectedID, "a")
    }

    // MARK: - Test 2: incremental prop patch preserves selection

    func testIncrementalPropPatchPreservesSelection() throws {
        let (coordinator, transport, _) = makeCoordinator()

        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "first"),
            (id: "b", title: "Bravo", subtitle: "second"),
            (id: "c", title: "Charlie", subtitle: "third"),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        // Select "b" (not the default first row).
        coordinator.select(id: "b")
        XCTAssertEqual(coordinator.selectedID, "b")

        // The host emits a minimal incremental patch: replace only item b's title.
        // List item "b" is at children[1] of the list at root.children[0].
        let bTitlePath = "/children/0/children/1/props/title"
        transport.deliverInbound(.notification(try renderNotification(
            revision: 2, patch: [.replace(bTitlePath, .string("Bravo!"))])))

        let list = try XCTUnwrap(coordinator.listViewModel)
        XCTAssertEqual(list.items.count, 3, "count unchanged after a prop-only patch")
        XCTAssertEqual(list.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(list.items[1].title, "Bravo!", "only b's title changed")
        XCTAssertEqual(list.items[0].title, "Alpha")
        XCTAssertEqual(list.items[2].title, "Charlie")
        XCTAssertEqual(coordinator.selectedID, "b", "selection survives an incremental prop patch")
    }

    // MARK: - Test 3: reorder (move) preserves selection by id

    func testReorderPreservesSelectionById() throws {
        let (coordinator, transport, _) = makeCoordinator()

        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "first"),
            (id: "b", title: "Bravo", subtitle: "second"),
            (id: "c", title: "Charlie", subtitle: "third"),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        coordinator.select(id: "c")
        XCTAssertEqual(coordinator.selectedID, "c")

        // Reorder: move the item at children[2] (c) to the front (children[0]).
        // Order becomes c, a, b. Because VeeJSONPatch honors the node `key` as
        // identity, the host emits a `move` rather than a remove+add.
        let listChildren = "/children/0/children"
        transport.deliverInbound(.notification(try renderNotification(
            revision: 2, patch: [.move(from: "\(listChildren)/2", to: "\(listChildren)/0")])))

        let list = try XCTUnwrap(coordinator.listViewModel)
        XCTAssertEqual(list.items.map(\.id), ["c", "a", "b"], "order changed via move")
        XCTAssertEqual(Set(list.items.map(\.id)).count, 3, "nothing duplicated or dropped")
        XCTAssertEqual(list.items.count, 3)
        XCTAssertEqual(coordinator.selectedID, "c", "selection follows the item by id across a reorder")
    }

    // MARK: - Selection rule: removed selection falls to the nearest surviving index

    func testRemovedSelectionFallsToNearestIndex() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "x"),
            (id: "b", title: "Bravo", subtitle: "y"),
            (id: "c", title: "Charlie", subtitle: "z"),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        // Select the last item, then remove it. Selection should clamp to the new
        // last surviving index (index 2 → clamp to 1 → "b").
        coordinator.select(id: "c")
        transport.deliverInbound(.notification(try renderNotification(
            revision: 2, patch: [.remove("/children/0/children/2")])))

        let list = try XCTUnwrap(coordinator.listViewModel)
        XCTAssertEqual(list.items.map(\.id), ["a", "b"])
        XCTAssertEqual(coordinator.selectedID, "b", "removed selection clamps to nearest surviving index")
    }

    func testRemovingMiddleSelectionKeepsSameIndex() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "x"),
            (id: "b", title: "Bravo", subtitle: "y"),
            (id: "c", title: "Charlie", subtitle: "z"),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        // Select the middle item (index 1), remove it; the item now at index 1
        // ("c") becomes selected.
        coordinator.select(id: "b")
        transport.deliverInbound(.notification(try renderNotification(
            revision: 2, patch: [.remove("/children/0/children/1")])))

        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["a", "c"])
        XCTAssertEqual(coordinator.selectedID, "c", "selection stays at the same index after middle removal")
    }

    // MARK: - Test 4: query → native filter, NO IPC on keystroke

    func testQueryFiltersNativelyWithoutIPC() throws {
        // A deterministic fuzzy stub: keeps only candidates whose id is in `keep`,
        // in that order, regardless of the scoring algorithm.
        let stub = StubFuzzyMatcher(keepIDs: ["fo", "foo"])
        let (coordinator, transport, _) = makeCoordinator(serverSideFiltering: false, fuzzy: stub)

        let candidates = [
            Candidate(id: "fo", title: "Foo Bar"),
            Candidate(id: "ba", title: "Baz Qux"),
            Candidate(id: "foo", title: "Foobar Two"),
        ]
        transport.deliverInbound(.notification(try setCandidatesNotification(candidates)))

        coordinator.setQuery("fo")

        // Visible items are exactly the fuzzy stub's output, in its order.
        XCTAssertEqual(stub.lastQuery, "fo")
        XCTAssertEqual(coordinator.visibleCandidates.map(\.id), ["fo", "foo"])

        // CRITICAL: a keystroke must NOT cross IPC when filtering natively.
        let searchFrames = outboundParams(transport, method: RPCMethods.onSearchTextChange, as: SearchTextChangeParams.self)
        XCTAssertEqual(searchFrames.count, 0, "native filtering must not send host.onSearchTextChange")

        // Now a server-filtering command DOES forward the keystroke exactly once.
        let serverStub = StubFuzzyMatcher(keepIDs: ["fo", "foo"])
        let (serverCoord, serverTransport, _) = makeCoordinator(serverSideFiltering: true, fuzzy: serverStub)
        serverTransport.deliverInbound(.notification(try setCandidatesNotification(candidates)))
        serverCoord.setQuery("fo")
        let serverFrames = outboundParams(serverTransport, method: RPCMethods.onSearchTextChange, as: SearchTextChangeParams.self)
        XCTAssertEqual(serverFrames.count, 1, "server-filtering command forwards the query once")
        XCTAssertEqual(serverFrames.first?.query, "fo")
        XCTAssertEqual(serverFrames.first?.pluginId, pluginId)
    }

    // MARK: - Test 5: action dispatch round-trips one host.invokeAction

    func testActionDispatchRoundTripsInvokeAction() throws {
        let (coordinator, transport, _) = makeCoordinator()

        let tree = listTree([
            (id: "a", title: "Alpha", subtitle: "first"),
            (id: "b", title: "Bravo", subtitle: "second"),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        coordinator.select(id: "b")
        // Invoke the selected item's (only) action.
        let action = try XCTUnwrap(coordinator.listViewModel?.items.first { $0.id == "b" }?.actions.first)
        coordinator.invoke(action: action.actionId)

        // Exactly one host.invokeAction notification, with the right ids, and it
        // round-trips through the codec (TestPeerTransport encodes on send).
        let invokes = outboundParams(transport, method: RPCMethods.invokeAction, as: InvokeActionParams.self)
        XCTAssertEqual(invokes.count, 1)
        XCTAssertEqual(invokes.first?.actionId, "open-b")
        XCTAssertEqual(invokes.first?.targetId, "b", "targetId == the selected item id")
        XCTAssertEqual(invokes.first?.pluginId, pluginId)
    }

    // MARK: - Bonus coverage: empty-view → empty-state VM; unknown tag → inert

    func testEmptyViewProjectsEmptyState() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = RenderNode(tag: RenderNode.Tag.root, props: [:], children: [
            RenderNode(tag: RenderNode.Tag.empty, props: [
                "title": .string("Nothing here"),
                "description": .string("Try another search"),
            ], children: []),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        XCTAssertNil(coordinator.listViewModel, "no list present")
        let empty = try XCTUnwrap(coordinator.emptyViewModel)
        XCTAssertEqual(empty.title, "Nothing here")
        XCTAssertEqual(empty.description, "Try another search")
    }

    func testDetailProjectsDetailViewModel() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = RenderNode(tag: RenderNode.Tag.root, props: [:], children: [
            RenderNode(tag: RenderNode.Tag.detail, props: [
                "title": .string("Readme"),
                "markdown": .string("# Hello\nbody"),
            ], children: []),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        let detail = try XCTUnwrap(coordinator.detailViewModel)
        XCTAssertEqual(detail.title, "Readme")
        XCTAssertEqual(detail.markdown, "# Hello\nbody")
    }

    // MARK: - Bonus coverage: out-of-order render revision is ignored

    func testOutOfOrderRevisionIgnored() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = listTree([(id: "a", title: "Alpha", subtitle: "x")])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 5, patch: [.replace("", tree.jsonValue)])))
        // A stale (lower-revision) frame must be dropped (it would also fail to
        // apply against the post-replace mirror, so dropping early is correct).
        transport.deliverInbound(.notification(try renderNotification(
            revision: 3, patch: [.replace("/children/0/children/0/props/title", .string("STALE"))])))
        XCTAssertEqual(coordinator.listViewModel?.items.first?.title, "Alpha")
    }

    // MARK: - Bonus coverage: lifecycle drives the injected host

    func testActivateDeactivateDriveHost() throws {
        let (coordinator, _, host) = makeCoordinator()
        coordinator.activate(command: "view", arguments: ["q": .string("hi")])
        XCTAssertEqual(host.activated.count, 1)
        XCTAssertEqual(host.activated.first?.commandName, "view")
        XCTAssertEqual(host.activated.first?.pluginId, pluginId)
        coordinator.deactivate(command: "view")
        XCTAssertEqual(host.deactivated.count, 1)
        XCTAssertEqual(host.deactivated.first?.commandName, "view")
    }

    // MARK: - Bonus coverage: window/menubar seams receive projected updates

    func testWindowSeamReceivesProjectedTree() throws {
        let transport = TestPeerTransport()
        let host = FakeHost()
        let window = SpyWindowPresenter()
        let menubar = SpyMenuBarPresenter()
        let coordinator = AppCoordinator(
            pluginId: pluginId, transport: transport, host: host,
            fuzzy: LiveFuzzyMatcher(), serverSideFiltering: false)
        coordinator.window = window
        coordinator.menuBar = menubar

        let tree = listTree([(id: "a", title: "Alpha", subtitle: "x")])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        // The window seam is handed the projected root view model.
        XCTAssertNotNil(window.lastRoot, "window seam should receive the projected tree")
        if case .list(let list)? = window.lastRoot {
            XCTAssertEqual(list.items.map(\.id), ["a"])
        } else {
            XCTFail("expected the root projection to be a list, got \(String(describing: window.lastRoot))")
        }
    }

    // MARK: - Host-native candidate mode (pluginless root search)

    func testHostCandidatesRenderAndInvokeLocallyWithoutTransport() {
        let (coordinator, transport, _) = makeCoordinator()
        var invoked: Candidate?
        let apps = [
            Candidate(id: "safari", title: "Safari"),
            Candidate(id: "mail", title: "Mail"),
            Candidate(id: "messages", title: "Messages"),
        ]
        coordinator.showHostCandidates(apps) { invoked = $0 }

        // Projected into the list surface (the pluginless root search).
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["safari", "mail", "messages"])
        XCTAssertEqual(coordinator.selectedID, "safari", "default selection is the first item")

        // Native fuzzy filter narrows the list with no IPC.
        coordinator.setQuery("mes")
        XCTAssertEqual(coordinator.listViewModel?.items.map(\.id), ["messages"])

        // Activating a row invokes the host callback locally — NOT a transport frame.
        coordinator.setQuery("")
        coordinator.select(id: "mail")
        coordinator.invoke(action: "vee.builtin.invoke")
        XCTAssertEqual(invoked?.id, "mail")
        XCTAssertTrue(
            outboundParams(transport, method: RPCMethods.invokeAction, as: InvokeActionParams.self).isEmpty,
            "host-native invoke must not send a host.invokeAction frame")
    }

    // MARK: - UX backlog #1: match highlighting threads matchedIndices through

    func testVisibleItemsCarryMatchedIndicesForQuery() {
        // Stub returns specific matched positions per candidate so we can assert
        // the indices survive the candidate → list-item projection (by id).
        let stub = IndexedFuzzyMatcher(matches: [
            "fo": [0, 1],      // "Foo Bar" → F, o
            "foo": [0, 1, 3],  // "Foobar Two" → F, o, b
        ])
        let (coordinator, transport, _) = makeCoordinator(serverSideFiltering: false, fuzzy: stub)

        let candidates = [
            Candidate(id: "fo", title: "Foo Bar"),
            Candidate(id: "ba", title: "Baz Qux"),
            Candidate(id: "foo", title: "Foobar Two"),
        ]
        transport.deliverInbound(.notification(try! setCandidatesNotification(candidates)))
        // Enter host-candidate mode so the candidates project into the list surface.
        coordinator.showHostCandidates(candidates) { _ in }

        coordinator.setQuery("fo")

        let items = try! XCTUnwrap(coordinator.listViewModel?.items)
        XCTAssertEqual(items.map(\.id), ["fo", "foo"], "filtered to the stub's matches")
        XCTAssertEqual(items.first { $0.id == "fo" }?.matchedIndices, [0, 1])
        XCTAssertEqual(items.first { $0.id == "foo" }?.matchedIndices, [0, 1, 3])

        // Clearing the query drops highlighting (empty query → plain titles).
        coordinator.setQuery("")
        let cleared = try! XCTUnwrap(coordinator.listViewModel?.items)
        XCTAssertTrue(cleared.allSatisfy { $0.matchedIndices.isEmpty },
                      "no query → no matched indices (plain titles)")
    }

    // MARK: - UX backlog #2: detail metadata rail parsing

    func testDetailViewModelParsesIconAndMetadata() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = RenderNode(tag: RenderNode.Tag.root, props: [:], children: [
            RenderNode(tag: RenderNode.Tag.detail, props: [
                "title": .string("Report.pdf"),
                "icon": .string("doc.richtext"),
                "markdown": .string("# Summary\nbody"),
                "metadata": .array([
                    .object(["label": .string("Size"), "value": .string("4.2 MB")]),
                    .object(["label": .string("Kind"), "value": .string("PDF")]),
                    // Malformed entries are skipped (missing value / not an object).
                    .object(["label": .string("Orphan")]),
                    .string("ignored"),
                ]),
            ], children: []),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        let detail = try XCTUnwrap(coordinator.detailViewModel)
        XCTAssertEqual(detail.title, "Report.pdf")
        XCTAssertEqual(detail.icon, "doc.richtext")
        XCTAssertEqual(detail.markdown, "# Summary\nbody")
        XCTAssertEqual(detail.metadata, [
            DetailMetadataRow(label: "Size", value: "4.2 MB"),
            DetailMetadataRow(label: "Kind", value: "PDF"),
        ], "well-formed {label,value} rows kept in order; malformed entries dropped")
    }

    func testDetailWithoutMetadataDefaultsToEmpty() throws {
        let (coordinator, transport, _) = makeCoordinator()
        let tree = RenderNode(tag: RenderNode.Tag.root, props: [:], children: [
            RenderNode(tag: RenderNode.Tag.detail, props: [
                "title": .string("Plain"),
                "markdown": .string("body"),
            ], children: []),
        ])
        transport.deliverInbound(.notification(try renderNotification(
            revision: 1, patch: [.replace("", tree.jsonValue)])))

        let detail = try XCTUnwrap(coordinator.detailViewModel)
        XCTAssertNil(detail.icon)
        XCTAssertEqual(detail.metadata, [], "no metadata prop → empty rail")
    }
}

// MARK: - Test doubles

/// A JSON-RPC transport peer for tests. Plays the launcher's half: tests deliver
/// inbound frames the host would write (`plugin.render`, …) via `deliverInbound`,
/// and the coordinator's outbound frames (`host.invokeAction`, …) are recorded in
/// `sent` after a real codec round-trip (so encodability is exercised).
final class TestPeerTransport: CoordinatorTransport {
    private(set) var sent: [JSONRPCMessage] = []
    private var inbound: ((JSONRPCMessage) -> Void)?

    func attachInbound(_ handler: @escaping (JSONRPCMessage) -> Void) {
        self.inbound = handler
    }

    func sendToHost(_ message: JSONRPCMessage) {
        // Round-trip through the real JSON-RPC codec so an un-encodable outbound
        // frame would surface here (mirrors LoopbackTransport.send).
        let decoded: JSONRPCMessage
        do {
            let data = try RPCCodec.encode(message)
            decoded = try RPCCodec.decode(data)
        } catch {
            XCTFail("RPCCodec.encode/decode failed for outbound frame: \(error)")
            decoded = message
        }
        sent.append(decoded)
    }

    /// Simulate the host writing a frame toward the launcher.
    func deliverInbound(_ message: JSONRPCMessage) {
        inbound?(message)
    }
}

/// Records lifecycle calls; the real `PluginHost` conforms to `PluginActivating`
/// in the library (verified by compilation, not exercised here).
final class FakeHost: PluginActivating {
    private(set) var activated: [ActivateParams] = []
    private(set) var deactivated: [DeactivateParams] = []
    func activate(_ params: ActivateParams) throws { activated.append(params) }
    func deactivate(_ params: DeactivateParams) { deactivated.append(params) }
}

/// Deterministic fuzzy stub: returns exactly the candidates whose id is in
/// `keepIDs`, in that order, ignoring the scoring algorithm. Records the query.
final class StubFuzzyMatcher: FuzzyMatching {
    let keepIDs: [String]
    private(set) var lastQuery: String?
    init(keepIDs: [String]) { self.keepIDs = keepIDs }
    func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        lastQuery = query
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return keepIDs.compactMap { id in
            byID[id].map { ScoredCandidate(candidate: $0, score: 1, matchedIndices: []) }
        }
    }
}

/// Fuzzy stub that returns explicit matched-character positions per candidate id
/// (and keeps only the ids present in `matches`, in dictionary-unstable order →
/// callers assert by id, not position). Exercises matchedIndices threading.
final class IndexedFuzzyMatcher: FuzzyMatching {
    let matches: [String: [Int]]
    init(matches: [String: [Int]]) { self.matches = matches }
    func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        candidates.compactMap { c in
            guard let indices = matches[c.id] else { return nil }
            return ScoredCandidate(candidate: c, score: 1, matchedIndices: indices)
        }
    }
}

/// Spy window seam capturing the last projected root view model.
final class SpyWindowPresenter: LauncherWindowPresenting {
    private(set) var lastRoot: RootViewModel?
    private(set) var shownCount = 0
    private(set) var hiddenCount = 0
    func setRootViewModel(_ root: RootViewModel?) { lastRoot = root }
    func showLauncher() { shownCount += 1 }
    func hideLauncher() { hiddenCount += 1 }
}

/// Spy menubar seam.
final class SpyMenuBarPresenter: MenuBarPresenting {
    private(set) var title: String?
    private(set) var items: [MenuBarItemViewModel] = []
    func setMenuBarTitle(_ title: String?) { self.title = title }
    func setMenuBarItems(_ items: [MenuBarItemViewModel]) { self.items = items }
}
