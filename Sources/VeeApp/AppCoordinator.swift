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

    /// The id whose inbound `plugin.render`/`setCandidates` frames this coordinator
    /// accepts, and that its outbound frames target. Starts as the launcher root id
    /// and is RETARGETED to a plugin's id when its command is activated (ARCH-1),
    /// so the plugin's renders are no longer filtered out. `showRoot()` restores it.
    public private(set) var pluginId: String
    /// The launcher root identity, restored by `showRoot()`.
    private let rootPluginId: String
    private let transport: CoordinatorTransport
    private let host: PluginActivating
    /// Resolves declared preference values + answers "is this command configured?"
    /// (the Raycast model). Optional so headless tests can omit it. When nil,
    /// activation is never gated and no preferences are delivered.
    private let preferences: PluginPreferenceProviding?
    /// Invoked INSTEAD of activating when a command's required preferences are
    /// unset — the app opens that extension's settings ("Setup required").
    /// Args: (pluginId, command).
    private let onNeedsConfiguration: ((String, String) -> Void)?
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
    /// Router for background menu-bar-command frames. The coordinator is the single
    /// inbound transport subscriber; frames whose `pluginId` is a registered
    /// menu-bar command are demuxed off the launcher surface and forwarded here
    /// (so a menu-bar plugin renders into its own status item, not the window).
    public weak var menuBarRouter: MenuBarRouting?
    /// Plugin ids that run as background menu-bar commands (see `menuBarRouter`).
    private var menuBarPluginIds: Set<String> = []

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
    /// PERF-2: assigning it re-folds the corpus ONCE (here), so the per-keystroke
    /// `refilter` scores the pre-prepared set without re-normalizing.
    private var candidates: [Candidate] = [] {
        didSet { preparedCandidates = fuzzy.prepare(candidates) }
    }
    /// Folded/boundary-masked projection of `candidates`, rebuilt only when the
    /// candidate set changes (once per open/refresh) — the PERF-2 hot-path cache.
    private var preparedCandidates: [PreparedCandidate] = []
    /// The natively-filtered candidates for the current query.
    public private(set) var visibleCandidates: [Candidate] = []
    /// Matched character positions per visible candidate id (from
    /// `ScoredCandidate.matchedIndices`), used to highlight the result title.
    /// Empty for the no-query pass (plain titles). Keyed by candidate id so it
    /// survives the candidate→list-item projection without index coupling.
    private var matchedIndicesByID: [String: [Int]] = [:]

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
    /// PERF-3: cap how many rows are turned into view models per (re)filter. The
    /// launcher shows ~10 rows and the set is score-ranked (best first), so
    /// building thousands of `ListItemViewModel`s per keystroke is pure waste;
    /// 200 is far beyond what a user scrolls yet bounds the pathological case.
    private static let maxProjectedRows = 200

    // MARK: Selection state

    /// The selected item id (list surface), preserved by id across patches.
    public private(set) var selectedID: String?

    // MARK: Init

    public init(pluginId: String,
                transport: CoordinatorTransport,
                host: PluginActivating,
                fuzzy: FuzzyMatching = LiveFuzzyMatcher(),
                serverSideFiltering: Bool = false,
                preferences: PluginPreferenceProviding? = nil,
                onNeedsConfiguration: ((String, String) -> Void)? = nil) {
        self.pluginId = pluginId
        self.rootPluginId = pluginId
        self.transport = transport
        self.host = host
        self.preferences = preferences
        self.onNeedsConfiguration = onNeedsConfiguration
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

    public var loadingViewModel: LoadingViewModel? {
        guard case .loading(let l) = root else { return nil }
        return l
    }

    /// R2-HIGH-4: the actions for the currently selected list item — what the ⌘K
    /// actions menu presents. Empty when there's no list surface, no selection, or
    /// the selected item carries no actions, so the GUI can treat `⌘K` as a no-op
    /// (never a misleading empty menu). In host-native mode the selected row's
    /// synthesized primary "Open" action is included (an item always has ≥1 action
    /// after projection), so ⌘K may legitimately show just "Open".
    public var actionsForSelection: [ActionViewModel] {
        guard case .list(let list) = root, let selectedID,
              let item = list.items.first(where: { $0.id == selectedID }) else { return [] }
        return item.actions
    }

    /// R2-HIGH-4: whether a ⌘K actions menu should open for the current selection.
    /// False (so ⌘K is a no-op) when there's nothing actionable to show. The GUI
    /// calls this on ⌘K and only presents the popover when it's true.
    public var canShowActionsMenu: Bool { !actionsForSelection.isEmpty }

    /// True while the cold-open loading surface is showing (R2-MED-4). Flips to
    /// false as soon as the first candidates or a plugin render replace it.
    public var isLoading: Bool {
        if case .loading = root { return true }
        return false
    }

    // MARK: - Inbound routing (host → launcher)

    private func handleInbound(_ message: JSONRPCMessage) {
        guard case .notification(let note) = message, let params = note.params else { return }
        // Demux: a frame for a registered background menu-bar command never drives
        // the launcher surface — forward it to the menu-bar router and stop.
        if let pid = params["pluginId"]?.stringValue, menuBarPluginIds.contains(pid) {
            menuBarRouter?.handleFrame(message)
            return
        }
        // Only handle frames addressed to our plugin (or unaddressed).
        if let pid = params["pluginId"]?.stringValue, pid != pluginId { return }

        switch note.method {
        case RPCMethods.render:
            if let p = try? decode(RenderParams.self, from: params) { applyRender(p) }
        case RPCMethods.setCandidates:
            if let p = try? decode(SetCandidatesParams.self, from: params) { applyCandidates(p.candidates) }
        case RPCMethods.toast:
            // UX-5: surface plugin toasts through the window seam (no coordinator
            // state). Style maps 1:1 onto the AppKit banner's appearance.
            if let p = try? decode(ToastParams.self, from: params) {
                let style: ToastStyle
                switch p.style {
                case .success: style = .success
                case .failure: style = .failure
                case .info:    style = .info
                }
                window?.presentToast(style: style, title: p.title, message: p.message)
            }
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

        // A plugin is now driving the surface — stop re-projecting the host-native
        // root candidates over its render on the next keystroke. `showRoot()`
        // re-enters host mode when the user backs out.
        hostCandidateMode = false

        // Capture the selection BEFORE mutating the mirror so we can preserve it.
        let previousSelection = selectedID
        let previousIDs = currentItemIDs()

        // Apply the patch to our own mirror. A whole-tree first render arrives as
        // `replace ""`; subsequent renders are minimal diffs.
        let base = mirror ?? .null
        guard let next = try? JSONPatch.apply(params.patch, to: base) else {
            // R2-MED-3 recovery: a patch that fails to apply means our mirror has
            // desynced from the host (e.g. a diff arrived against a tree we never
            // saw). The host has ALREADY advanced its revision, so every later diff
            // would mis-apply onto this stale base and the surface would freeze
            // permanently. Instead of returning (and keeping the poisoned mirror),
            // RESET: drop the mirror + revision sequence so we stop applying diffs
            // onto a desynced base, and show a neutral "refreshing" surface. The
            // host re-renders the whole tree as a `replace ""` keyframe (revision
            // restarts above 0), which then re-syncs cleanly from `.null`.
            resetMirrorForResync()
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

    /// R2-MED-3 recovery: drop the render mirror to a clean slate after a failed
    /// patch apply so the surface can't stay frozen on a desynced tree. Clears the
    /// mirror and resets `lastRevision` to 0 — the host's next full render (a
    /// `replace ""` keyframe at any revision ≥ 1) then passes the staleness guard
    /// and rebuilds the tree from `.null`. Drops to a subtle "Refreshing…" empty
    /// state in the meantime (rather than a blank pane) and clears selection.
    private func resetMirrorForResync() {
        mirror = nil
        lastRevision = 0
        selectedID = nil
        root = .empty(EmptyViewModel(title: "Refreshing…", description: nil))
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

    /// Show the cold-open loading surface (R2-MED-4): a "Loading…" indicator while
    /// app discovery + the ~5000-app enumeration are still running, so the panel
    /// gives feedback instead of a blank list. main.swift calls this at startup;
    /// the first `showHostCandidates`/`applyRender` clears it automatically.
    public func showLoading(title: String? = "Loading…", description: String? = nil) {
        selectedID = nil
        root = .loading(LoadingViewModel(title: title, description: description))
        pushToWindow()
    }

    /// Display a host-native candidate set (e.g. installed apps) as the launcher
    /// list — the pluginless "root search" surface. `invoke` is called with the
    /// activated candidate (e.g. to launch the app). No plugin/transport involved.
    /// Clears any cold-open loading surface (R2-MED-4) since real content arrived.
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

    /// Re-enter the host-native root surface (the app/command list) — e.g. when
    /// the launcher reopens after a plugin command had taken over the surface.
    /// Restores the last `showHostCandidates` set with a cleared query.
    public func showRoot() {
        pluginId = rootPluginId   // ARCH-1: back to the launcher identity
        lastRevision = 0          // ARCH-3: drop the plugin's mirror + revision seq
        mirror = nil
        query = ""
        hostCandidateMode = true
        refilter()
    }

    /// Register `pluginId` as a background menu-bar command: its inbound `plugin.*`
    /// frames are demuxed off the launcher surface and forwarded to `menuBarRouter`
    /// (the plugin renders into its own status item, never the launcher window).
    public func registerMenuBarPlugin(_ pluginId: String) {
        menuBarPluginIds.insert(pluginId)
    }

    /// Activate a plugin command and RETARGET this coordinator to that plugin's id
    /// so its `plugin.render`/`setCandidates` frames are accepted (ARCH-1), with a
    /// fresh render-revision sequence (ARCH-3, mirror reset so the plugin's first
    /// `revision: 1` isn't dropped as stale). Leaves the host-native root surface;
    /// `showRoot()` returns to it.
    public func activatePlugin(_ pluginId: String, command: String,
                               arguments: [String: JSONValue] = [:]) {
        // Raycast-style "Setup required": when the plugin declared required
        // preferences the user hasn't set, surface configuration instead of
        // running — and DON'T retarget, so the launcher stays on its root.
        if let preferences, !preferences.isConfigured(pluginId: pluginId, command: command) {
            onNeedsConfiguration?(pluginId, command)
            return
        }
        self.pluginId = pluginId
        hostCandidateMode = false
        lastRevision = 0
        mirror = nil
        let resolved = preferences?.resolvedValues(pluginId: pluginId, command: command) ?? [:]
        try? host.activate(ActivateParams(pluginId: pluginId, commandName: command,
                                          arguments: arguments, preferences: resolved))
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

    /// Re-run the native fuzzy filter over the held candidate set. Keeps the
    /// scored results (NOT just `.candidate`) so match positions survive into the
    /// projected items for title highlighting.
    private func refilter() {
        if query.isEmpty {
            // No query → all candidates in input order, plain titles (no indices).
            visibleCandidates = candidates
            matchedIndicesByID = [:]
        } else {
            let scored = fuzzy.match(query: query, inPrepared: preparedCandidates)
            visibleCandidates = scored.map(\.candidate)
            matchedIndicesByID = Dictionary(
                scored.map { ($0.candidate.id, $0.matchedIndices) },
                uniquingKeysWith: { first, _ in first })
        }
        if hostCandidateMode { projectHostCandidates() }
    }

    /// Project `visibleCandidates` into the list surface (host-native mode only).
    /// Each candidate becomes a list item; candidates with no actions get a
    /// synthesized primary "Open" action so the GUI has something to invoke.
    private func projectHostCandidates() {
        let items = visibleCandidates.prefix(Self.maxProjectedRows).map { c in
            ListItemViewModel(
                id: c.id, title: c.title, subtitle: c.subtitle, icon: c.icon,
                accessoryText: hostAccessory,
                actions: c.actions.isEmpty
                    ? [ActionViewModel(actionId: Self.builtinActionId, title: "Open")]
                    : c.actions.map { ActionViewModel(actionId: $0.id, title: $0.title, shortcut: $0.shortcut) },
                matchedIndices: matchedIndicesByID[c.id] ?? [])
        }
        // No matches → a proper empty state, never a section header with zero
        // rows (which reads as a bug). Only when there's an active query, though:
        // an empty candidate set with no query just means "not loaded yet".
        if items.isEmpty && !query.isEmpty {
            selectedID = nil
            root = .empty(EmptyViewModel(
                title: "No Results",
                description: "No apps or commands match “\(query)”."))
            pushToWindow()
            return
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
        let resolved = preferences?.resolvedValues(pluginId: pluginId, command: command) ?? [:]
        try host.activate(ActivateParams(pluginId: pluginId, commandName: command,
                                         arguments: arguments, preferences: resolved))
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
        case .detail, .empty, .loading, .none:
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
