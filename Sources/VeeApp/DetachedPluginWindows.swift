import AppKit
import SwiftUI
import VeeMenu
import VeePluginFormat
import VeeSearch
import VeeUI

/// How a detached window sits relative to everything else on screen.
///
/// Level and collection behavior are resolved **together, here, and nowhere
/// else**. They are not independent settings: a `.floating` window left on the
/// default `.managed` behavior is hidden the moment another app goes full-screen
/// and stays behind on the Space it was born on — which is precisely the
/// situation floating exists to survive, so the pair is the unit that has
/// meaning, not either half.
///
/// Pure, so the pairing is unit-testable without ever constructing a window.
enum DetachedWindowPinning {
    static func settings(pinned: Bool) -> (level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) {
        pinned
            // Follow the user across Spaces, and stay visible over a full-screen
            // app — "watch a value while working elsewhere" includes working
            // full-screen, which is where the default behavior would fail.
            ? (.floating, [.canJoinAllSpaces, .fullScreenAuxiliary])
            // An ordinary window: Mission Control reaches it (the only system
            // retrieval path that works for an accessory app) and Spaces treat
            // it normally.
            : (.normal, [.managed])
    }

    @MainActor
    static func apply(_ pinned: Bool, to window: NSWindow) {
        let settings = settings(pinned: pinned)
        window.level = settings.level
        window.collectionBehavior = settings.behavior
    }
}

/// Backing state for one detached window: the plugin's searchable menu, whether
/// its content is still current, and whether it floats.
@MainActor
final class DetachedPluginWindowModel: ObservableObject {
    let pluginName: String
    /// The same view model the transient panel uses — the two presentations
    /// share it, which is what keeps them from drifting on what a row means.
    let search: MenuSearchViewModel
    /// Set when nothing is feeding this window any more: the plugin was
    /// disabled, removed, or is failing. The window keeps showing the last
    /// output it saw rather than blanking — a frozen reading that looks live is
    /// worse than one that admits it is frozen.
    @Published var isStale = false
    @Published var isPinned: Bool

    init(pluginName: String, nodes: [MenuTreeNode], isPinned: Bool) {
        self.pluginName = pluginName
        self.search = MenuSearchViewModel(nodes: nodes)
        self.isPinned = isPinned
    }

    func update(nodes: [MenuTreeNode]) {
        search.update(nodes: nodes)
        isStale = false
    }
}

/// The plugin actions a window offers, the same set its dropdown's footer does.
///
/// Carried as plain closures taken from the controller's existing footer
/// targets, so operating a plugin from the window it is being watched in runs
/// exactly what operating it from the menu bar runs — there is no second action
/// path to keep in step.
struct PluginWindowControls {
    var onRefresh: () -> Void = {}
    var onSettings: () -> Void = {}
    var onAbout: () -> Void = {}
    var onReveal: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDebug: () -> Void = {}
}

/// A detached window's contents: the shared menu surface, its plugin's
/// controls, plus a note when the plugin stops reporting.
private struct DetachedPluginWindowView: View {
    @ObservedObject var model: DetachedPluginWindowModel
    let onActivate: (MenuRowSpec) -> Void
    let onCommit: @MainActor (MenuRowSpec, Double) -> Void
    let controls: PluginWindowControls

    var body: some View {
        VStack(spacing: 0) {
            MenuSearchContentView(
                model: model.search,
                pluginName: model.pluginName,
                onActivate: onActivate,
                onCommit: onCommit
            )
            if model.isStale {
                Divider()
                staleNote
            }
            Divider()
            controlBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The plugin's own controls, in the window's chrome rather than among its
    /// rows — they are Vee's actions, not the plugin's output, so the filter
    /// never matches them and they can't be confused for menu content.
    private var controlBar: some View {
        HStack(spacing: 8) {
            Button(action: controls.onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .help("Re-run \(model.pluginName)")

            Spacer(minLength: 0)

            Menu {
                Button("Settings…", action: controls.onSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("About \(model.pluginName)…", action: controls.onAbout)
                Divider()
                Button("Reveal in Finder", action: controls.onReveal)
                Button("Edit Plugin…", action: controls.onEdit)
                Button("Debug…", action: controls.onDebug)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Plugin actions")
            .accessibilityLabel("Plugin actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var staleNote: some View {
        Label(
            "\(model.pluginName) is no longer reporting — showing the last output.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The pin control, shown in the window's title bar rather than in its content —
/// the content is shared with the transient panel, which has nothing to pin.
private struct PinButton: View {
    @ObservedObject var model: DetachedPluginWindowModel
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            model.isPinned.toggle()
            onChange(model.isPinned)
        } label: {
            Image(systemName: model.isPinned ? "pin.fill" : "pin.slash")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .help(model.isPinned ? "Stop floating above other apps" : "Float above other apps")
        .accessibilityLabel("Float above other apps")
        .accessibilityValue(model.isPinned ? "on" : "off")
    }
}

/// Presents and tracks detached plugin windows — one per plugin, each a live
/// view of that plugin's whole menu surface.
///
/// Deliberately the same shape as `DebugWindowManager` (`VeeUI`), the other
/// window that keeps updating while its plugin re-runs: keyed by plugin, focus
/// rather than duplicate on re-invoke, and close-observer tokens owned in
/// manager state rather than captured by the observer closure. Kept identical so
/// the two read the same way.
@MainActor
final class DetachedPluginWindows {
    static let shared = DetachedPluginWindows()

    /// Skips ever constructing a real `NSWindow` — the same hazard/seam
    /// `CompactMenuBarController.attachesStatusItem` and
    /// `MainMenuController.attachesStatusItem` guard against. Hosting SwiftUI in
    /// a window from a unit test needs a live `NSApplication`; the bookkeeping
    /// below (which plugins are open, their pin state, their staleness, what the
    /// menu would list) is the part worth asserting, and it runs identically
    /// either way because it is keyed off `models`, never off `windows`.
    private let attachesWindows: Bool

    private var windows: [String: NSWindow] = [:]
    private var models: [String: DetachedPluginWindowModel] = [:]
    private var observerTokens: [String: NSObjectProtocol] = [:]
    private var controlsByPlugin: [String: PluginWindowControls] = [:]
    /// Pin state per plugin, remembered for the session. A window that reopens
    /// unpinned when the user last left it unpinned is the difference between a
    /// preference and a chore.
    private var pinPreference: [String: Bool] = [:]
    /// Running cascade origin, so each new window steps down-right of the last.
    /// `.zero` makes the first `cascadeTopLeft(from:)` a no-op, which is the
    /// documented way to seed it.
    private var cascadePoint: NSPoint = .zero

    init(attachesWindows: Bool = true) {
        self.attachesWindows = attachesWindows
    }

    /// Plugins with an open window, in a stable order for the menu listing.
    var openPlugins: [String] { models.keys.sorted() }

    var isEmpty: Bool { models.isEmpty }

    /// Whether `pluginName`'s window currently floats above other apps.
    func isPinned(pluginName: String) -> Bool {
        models[pluginName]?.isPinned ?? pinPreference[pluginName] ?? true
    }

    /// The level/behavior pair `pluginName`'s window is currently set to —
    /// directly assertable without reading a real window back.
    func pinning(pluginName: String) -> (level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) {
        DetachedWindowPinning.settings(pinned: isPinned(pluginName: pluginName))
    }

    /// Flips `pluginName`'s window between floating and ordinary. The control in
    /// the title bar routes here, so the two paths cannot diverge.
    func setPinned(_ pinned: Bool, pluginName: String) {
        models[pluginName]?.isPinned = pinned
        pinPreference[pluginName] = pinned
        guard let window = windows[pluginName] else { return }
        DetachedWindowPinning.apply(pinned, to: window)
    }

    func isStale(pluginName: String) -> Bool { models[pluginName]?.isStale ?? false }

    /// The row titles `pluginName`'s window is currently showing. A plain,
    /// directly assertable mirror of what the window would draw — the content
    /// itself lives behind a view model, and no test has a real window to read
    /// back.
    func visibleRowTitles(pluginName: String) -> [String] {
        guard let model = models[pluginName] else { return [] }
        return model.search.visible.compactMap { $0.row?.spec.item.text }
    }

    /// The controls `pluginName`'s window was opened with — directly
    /// assertable without a real window to click.
    func controls(pluginName: String) -> PluginWindowControls? { controlsByPlugin[pluginName] }

    /// Opens a branch in `pluginName`'s window by title path — the directly
    /// assertable half of expansion, with no window to read back.
    func toggleBranch(pluginName: String, key: MenuPath) {
        models[pluginName]?.search.toggle(key)
    }

    /// Whether `key`'s branch is currently open in `pluginName`'s window.
    func isBranchExpanded(pluginName: String, key: MenuPath) -> Bool {
        models[pluginName]?.search.isExpanded(key) ?? false
    }

    // MARK: - Opening

    /// Opens `pluginName`'s window, or focuses it if it is already open.
    ///
    /// `handler` is the plugin's own action handler, so a row activated here
    /// runs exactly what activating it in the dropdown runs, through the same
    /// dispatcher — there is no parallel action model.
    func show(
        pluginName: String,
        body: [MenuNode],
        handler: MenuActionHandling,
        controls: PluginWindowControls = PluginWindowControls()
    ) {
        let nodes = MenuTree.build(body)

        if let existing = models[pluginName] {
            existing.update(nodes: nodes)
            if let window = windows[pluginName] { focus(window) }
            return
        }

        let pinned = pinPreference[pluginName] ?? true
        let model = DetachedPluginWindowModel(pluginName: pluginName, nodes: nodes, isPinned: pinned)
        let root = DetachedPluginWindowView(
            model: model,
            onActivate: { [weak handler] row in handler?.perform(row.item) },
            onCommit: { [weak handler] row, value in handler?.commitControl(row.item, value: value) },
            controls: controls
        )

        models[pluginName] = model
        controlsByPlugin[pluginName] = controls
        guard attachesWindows else { return }

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = pluginName
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // An explicit size rather than the hosting controller's fitting size:
        // the content fills its window (so resizing is useful), which makes
        // "fits" ambiguous.
        window.setContentSize(Self.initialSize)
        // No frame autosave and no restoration: these windows are session-scoped
        // by design, like every other window Vee opens.
        DetachedWindowPinning.apply(pinned, to: window)
        addPinButton(to: window, model: model, pluginName: pluginName)

        // Cascade rather than stack: opening three of these to watch side by
        // side is the point, and three windows centred on top of each other
        // would look like one.
        window.center()
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)

        windows[pluginName] = window

        // Clear the entry when the window closes *any* way, including the
        // title-bar button — otherwise the key stays tracked forever and
        // reopening would focus a window the user already dismissed.
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose(pluginName) }
        }
        observerTokens[pluginName] = token

        focus(window)
    }

    /// Brings an already-open window to the front. No-op when the plugin has
    /// none, so a hotkey bound to a plugin without a window does nothing rather
    /// than opening one behind the user's back.
    func focus(pluginName: String) {
        guard let window = windows[pluginName] else { return }
        focus(window)
    }

    private func focus(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static let initialSize = NSSize(width: 440, height: 520)

    // MARK: - Liveness

    /// Records a plugin's freshly parsed dropdown into its open window. Called
    /// from `StatusItemController.render` — the one place new output reaches the
    /// UI, and therefore the one place a window can be kept live.
    func update(pluginName: String, body: [MenuNode]) {
        guard let model = models[pluginName] else { return }
        model.update(nodes: MenuTree.build(body))
    }

    /// Marks a plugin's window stale — its plugin is failing, disabled, or gone.
    /// The window keeps its last output on screen.
    func markStale(pluginName: String) {
        models[pluginName]?.isStale = true
    }

    /// Clears the stale flag without re-flattening. For the byte-identical
    /// render path: the plugin *is* reporting again, so a window marked stale by
    /// an earlier failure must stop saying so — but its content has not changed,
    /// and re-flattening a menu-sized tree on every tick of a 1-second plugin to
    /// arrive at the same entries would be work for nothing.
    func markFresh(pluginName: String) {
        models[pluginName]?.isStale = false
    }

    // MARK: - Pinning

    private func addPinButton(to window: NSWindow, model: DetachedPluginWindowModel, pluginName: String) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let hosting = NSHostingView(
            rootView: PinButton(model: model) { [weak self] pinned in
                self?.setPinned(pinned, pluginName: pluginName)
            }
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 36, height: 26)
        accessory.view = hosting
        window.addTitlebarAccessoryViewController(accessory)
    }

    // MARK: - Closing

    func close(pluginName: String) {
        guard let window = windows[pluginName] else {
            // No real window (tests): run the same eviction its close observer
            // would have, so tracking ends up in the identical state.
            windowWillClose(pluginName)
            return
        }
        window.close()
    }

    func closeAll() {
        for pluginName in openPlugins { close(pluginName: pluginName) }
    }

    /// Evicts the closed window and unregisters its close observer — a leftover
    /// registration (and the model its block retains) would otherwise accumulate
    /// once per window ever opened. The pin preference deliberately outlives the
    /// window, for the session.
    private func windowWillClose(_ pluginName: String) {
        windows[pluginName] = nil
        models[pluginName] = nil
        controlsByPlugin[pluginName] = nil
        if let token = observerTokens.removeValue(forKey: pluginName) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
