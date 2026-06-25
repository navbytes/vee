import Foundation
import VeeProtocol
import VeeEngine
import VeeServices
import VeeFuzzy
import VeeJSONPatch

/// Drives the launcher as a JSON-RPC transport PEER (docs/ARCHITECTURE.md §3, §5).
///
/// The coordinator does NOT call the host's render API. The host diffs each
/// `vee.render` and writes a `plugin.render` notification (carrying a
/// `RenderParams{pluginId, revision, patch}`) toward the launcher; the coordinator:
///   • attaches to the inbound peer stream (`CoordinatorTransport.attachInbound`),
///   • keeps its OWN `JSONValue` render mirror and applies inbound `patch`es with
///     `VeeJSONPatch.apply`, then reconstructs a `RenderNode` and projects view
///     models (the "view-model shielding" layer — `ViewModelProjector`),
///   • holds the candidate set from inbound `plugin.setCandidates` and filters it
///     per keystroke with an injected `FuzzyMatching` (NEVER round-trips on a
///     keystroke unless the command opted into server-side filtering),
///   • sends host→plugin frames (`host.invokeAction`, `host.onSearchTextChange`,
///     `host.submitForm`) back over the transport,
///   • drives lifecycle (`activate`/`deactivate`) via an injected `PluginActivating`.
///
/// Selection survives list patches by id: before applying an inbound list patch
/// we capture `selectedID`; after re-projecting we keep it if still present, else
/// select the nearest surviving index (clamped), else clear.
///
/// All logic lives here (testable). AppKit/menubar/hotkey/OS code sits behind the
/// `LauncherWindowPresenting` / `MenuBarPresenting` seams and the host-native
/// providers, which are thin and verified manually.
public final class AppCoordinator {

    // MARK: Identity & collaborators

    public let pluginId: String
    private let transport: CoordinatorTransport
    private let host: PluginActivating
    private let fuzzy: FuzzyMatching
    /// When true this command filters server-side: a keystroke ALSO forwards a
    /// `host.onSearchTextChange` frame (in addition to the native pre-filter).
    /// When false (the default), keystrokes never cross IPC.
    private let serverSideFiltering: Bool

    // MARK: AppKit seams (optional; nil in headless tests unless injected)

    public weak var window: LauncherWindowPresenting? {
        didSet {
            // Hand the window its intent sink (self) and an initial projection so
            // the GUI can forward gestures and render immediately. Pure wiring —
            // no behavior change; spies receive a no-op `attach`.
            window?.attach(intentHandler: self)
            pushToWindow()
        }
    }
    public weak var menuBar: MenuBarPresenting?

    // MARK: Render mirror state

    /// The launcher's own mirror of the plugin's render tree, as the canonical
    /// `JSONValue` wire projection. Inbound patches apply against this.
    private var mirror: JSONValue?
    /// Last applied render revision; out-of-order (stale) frames are dropped.
    private var lastRevision = 0
    /// The current projected primary surface (list / detail / empty / none).
    private var root: RootViewModel = .none

    // MARK: Query / candidate state

    private var query: String = ""
    /// The full candidate set pushed by the plugin (`plugin.setCandidates`).
    private var candidates: [Candidate] = []
    /// The natively-filtered candidates for the current query.
    public private(set) var visibleCandidates: [Candidate] = []

    /// Host-native "root search" mode (no plugin). When on, `visibleCandidates`
    /// are projected directly into the list surface and activating a row calls
    /// `candidateInvoke` instead of sending a `host.invokeAction` transport frame.
    /// This is the pluginless launcher surface (e.g. installed-app search).
    private var hostCandidateMode = false
    private var candidateInvoke: ((Candidate) -> Void)?
    private var hostSectionTitle: String?
    private var hostAccessory: String?
    /// Synthesized primary-action id for host candidates that declare none.
    private static let builtinActionId = "vee.builtin.invoke"

    // MARK: Selection state

    /// The selected item id (list surface), preserved by id across patches.
    public private(set) var selectedID: String?

    // MARK: Init

    public init(pluginId: String,
                transport: CoordinatorTransport,
                host: PluginActivating,
                fuzzy: FuzzyMatching = LiveFuzzyMatcher(),
                serverSideFiltering: Bool = false) {
        self.pluginId = pluginId
        self.transport = transport
        self.host = host
        self.fuzzy = fuzzy
        self.serverSideFiltering = serverSideFiltering

        // Attach to the inbound peer stream (mirror the Recorder pattern).
        self.transport.attachInbound { [weak self] message in
            self?.handleInbound(message)
        }
    }

    // MARK: - Projected view-model accessors

    /// The current primary surface for the launcher window.
    public var rootViewModel: RootViewModel { root }

    /// The list view model (with the live `selectedID` projected in), or nil if
    /// the current surface isn't a list.
    public var listViewModel: ListViewModel? {
        guard case .list(var list) = root else { return nil }
        list.selectedID = selectedID
        return list
    }

    public var detailViewModel: DetailViewModel? {
        guard case .detail(let d) = root else { return nil }
        return d
    }

    public var emptyViewModel: EmptyViewModel? {
        guard case .empty(let e) = root else { return nil }
        return e
    }

    // MARK: - Inbound routing (host → launcher)

    private func handleInbound(_ message: JSONRPCMessage) {
        guard case .notification(let note) = message, let params = note.params else { return }
        // Only handle frames addressed to our plugin (or unaddressed).
        if let pid = params["pluginId"]?.stringValue, pid != pluginId { return }

        switch note.method {
        case RPCMethods.render:
            if let p = try? decode(RenderParams.self, from: params) { applyRender(p) }
        case RPCMethods.setCandidates:
            if let p = try? decode(SetCandidatesParams.self, from: params) { applyCandidates(p.candidates) }
        case RPCMethods.toast:
            // UI affordance; surfaced via the window seam in production. No state.
            break
        case RPCMethods.log:
            // Logs are streamed to the console in production; no launcher state.
            break
        default:
            break
        }
    }

    // MARK: - Render application (mirror → patch → reproject, preserving selection)

    private func applyRender(_ params: RenderParams) {
        // Drop stale frames: the host emits monotonically-increasing revisions;
        // anything not strictly newer is out of order and ignored.
        guard params.revision > lastRevision else { return }

        // Capture the selection BEFORE mutating the mirror so we can preserve it.
        let previousSelection = selectedID
        let previousIDs = currentItemIDs()

        // Apply the patch to our own mirror. A whole-tree first render arrives as
        // `replace ""`; subsequent renders are minimal diffs.
        let base = mirror ?? .null
        guard let next = try? JSONPatch.apply(params.patch, to: base) else {
            // A patch that fails to apply (e.g. against an unexpected mirror) is
            // dropped rather than corrupting state; production would also log it.
            return
        }
        mirror = next
        lastRevision = params.revision

        // Reconstruct the RenderNode and project the primary surface.
        guard let node = try? RenderNode(jsonValue: next) else { return }
        root = ViewModelProjector.project(node)

        reconcileSelection(previousSelection: previousSelection, previousIDs: previousIDs)
        pushToWindow()
    }

    /// Re-establish selection after a re-projection (selection-preservation-by-id):
    /// keep the prior id if it still exists; else select the nearest surviving
    /// index (clamped to the new list); else clear.
    private func reconcileSelection(previousSelection: String?, previousIDs: [String]) {
        guard case .list(let list) = root else {
            // No list surface → no selection.
            selectedID = nil
            return
        }
        let ids = list.items.map(\.id)
        guard !ids.isEmpty else { selectedID = nil; return }

        if let sel = previousSelection, ids.contains(sel) {
            selectedID = sel                     // survived → keep it
            return
        }
        if let sel = previousSelection,
           let oldIndex = previousIDs.firstIndex(of: sel) {
            // Selected id is gone: fall to the nearest surviving index (clamp).
            let clamped = min(oldIndex, ids.count - 1)
            selectedID = ids[clamped]
            return
        }
        // No prior selection (or it was never in a list) → default to first.
        selectedID = ids.first
    }

    /// The item ids of the current list surface (empty if not a list).
    private func currentItemIDs() -> [String] {
        guard case .list(let list) = root else { return [] }
        return list.items.map(\.id)
    }

    // MARK: - Candidate handling (fetch once)

    private func applyCandidates(_ candidates: [Candidate]) {
        self.candidates = candidates
        refilter()
    }

    /// Display a host-native candidate set (e.g. installed apps) as the launcher
    /// list — the pluginless "root search" surface. `invoke` is called with the
    /// activated candidate (e.g. to launch the app). No plugin/transport involved.
    public func showHostCandidates(_ candidates: [Candidate],
                                   sectionTitle: String? = nil,
                                   accessory: String? = nil,
                                   invoke: @escaping (Candidate) -> Void) {
        hostCandidateMode = true
        candidateInvoke = invoke
        hostSectionTitle = sectionTitle
        hostAccessory = accessory
        self.candidates = candidates
        refilter()
    }

    // MARK: - Query / native filter (filter natively per keystroke)

    /// Set the search query. Filters the candidate set natively (no IPC). If the
    /// command opted into server-side filtering, ALSO forwards the query to the
    /// plugin via exactly one `host.onSearchTextChange` frame.
    public func setQuery(_ query: String) {
        self.query = query
        refilter()
        if serverSideFiltering {
            transport.notify(
                method: RPCMethods.onSearchTextChange,
                params: SearchTextChangeParams(pluginId: pluginId, query: query))
        }
    }

    public var currentQuery: String { query }

    /// Re-run the native fuzzy filter over the held candidate set.
    private func refilter() {
        if query.isEmpty {
            visibleCandidates = candidates
        } else {
            visibleCandidates = fuzzy.match(query: query, in: candidates).map(\.candidate)
        }
        if hostCandidateMode { projectHostCandidates() }
    }

    /// Project `visibleCandidates` into the list surface (host-native mode only).
    /// Each candidate becomes a list item; candidates with no actions get a
    /// synthesized primary "Open" action so the GUI has something to invoke.
    private func projectHostCandidates() {
        let items = visibleCandidates.map { c in
            ListItemViewModel(
                id: c.id, title: c.title, subtitle: c.subtitle, icon: c.icon,
                accessoryText: hostAccessory,
                actions: c.actions.isEmpty
                    ? [ActionViewModel(actionId: Self.builtinActionId, title: "Open")]
                    : c.actions.map { ActionViewModel(actionId: $0.id, title: $0.title, shortcut: $0.shortcut) })
        }
        // Search semantics: the top (best-ranked) match is selected on every
        // (re)filter, so Return launches the most relevant result. Arrow-key
        // navigation goes through `moveSelection`, which doesn't re-filter, so it
        // isn't clobbered.
        selectedID = items.first?.id
        root = .list(ListViewModel(items: items, selectedID: selectedID, sectionTitle: hostSectionTitle))
        pushToWindow()
    }

    // MARK: - Selection control (from the view)

    /// Select an item by id (no-op if it isn't present in the current list).
    public func select(id: String) {
        guard case .list(let list) = root, list.items.contains(where: { $0.id == id }) else { return }
        selectedID = id
        pushToWindow()
    }

    /// Move the selection by `delta` rows within the current list (clamped).
    public func moveSelection(by delta: Int) {
        guard case .list(let list) = root, !list.items.isEmpty else { return }
        let ids = list.items.map(\.id)
        let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = max(0, min(ids.count - 1, current + delta))
        selectedID = ids[next]
        pushToWindow()
    }

    // MARK: - Action dispatch (host → plugin)

    /// Invoke `actionId` on the currently selected item (targetId == selectedID).
    /// Sends exactly one `host.invokeAction` notification over the transport.
    public func invoke(action actionId: String) {
        invoke(action: actionId, targetId: selectedID)
    }

    /// Invoke an action with an explicit target id. In host-native mode this
    /// activates the targeted candidate locally (e.g. launches the app) instead
    /// of sending a `host.invokeAction` frame; otherwise it forwards to the plugin.
    public func invoke(action actionId: String, targetId: String?) {
        if hostCandidateMode {
            let id = targetId ?? selectedID
            if let id, let candidate = visibleCandidates.first(where: { $0.id == id })
                ?? candidates.first(where: { $0.id == id }) {
                candidateInvoke?(candidate)
            }
            return
        }
        transport.notify(
            method: RPCMethods.invokeAction,
            params: InvokeActionParams(pluginId: pluginId, actionId: actionId, targetId: targetId))
    }

    /// Submit a form (host → plugin). Sends one `host.submitForm` notification.
    public func submitForm(actionId: String, values: [String: JSONValue]) {
        transport.notify(
            method: RPCMethods.submitForm,
            params: SubmitFormParams(pluginId: pluginId, actionId: actionId, values: values))
    }

    // MARK: - Lifecycle (drives the injected host)

    /// Activate a command on the host. Throwing is swallowed into nothing here at
    /// the public boundary the GUI calls; callers that need the error use
    /// `activateThrowing`.
    public func activate(command: String, arguments: [String: JSONValue] = [:]) {
        try? activateThrowing(command: command, arguments: arguments)
    }

    public func activateThrowing(command: String, arguments: [String: JSONValue] = [:]) throws {
        try host.activate(ActivateParams(pluginId: pluginId, commandName: command, arguments: arguments))
    }

    public func deactivate(command: String) {
        host.deactivate(DeactivateParams(pluginId: pluginId, commandName: command))
    }

    // MARK: - Window push

    /// Hand the current projected surface (with live selection) to the window seam.
    private func pushToWindow() {
        guard let window else { return }
        switch root {
        case .list:
            window.setRootViewModel(listViewModel.map(RootViewModel.list))
        case .detail, .empty, .none:
            window.setRootViewModel(root)
        }
    }

    // MARK: - Decoding helper

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Intent sink for the launcher window

/// The coordinator IS the launcher's intent handler: every method the window
/// needs (`setQuery`/`select`/`moveSelection`/`invoke`) already exists above with
/// the matching signature, so conformance is a no-op declaration. Keeps the view
/// layer decoupled from the concrete coordinator type.
extension AppCoordinator: LauncherIntentHandling {}
