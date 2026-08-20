import AppKit
import SwiftUI
import VeePluginFormat
import VeeUI

/// Identifies the menu row a detached window is watching: which plugin, and
/// where the row sits in that plugin's dropdown tree.
///
/// Keyed by *position* rather than text on purpose — see `MenuItemLocator`. A
/// row worth watching is one whose text keeps changing, so text is the one thing
/// that can't identify it.
struct DetachedPopoverKey: Hashable {
    let pluginName: String
    let path: MenuItemPath
}

/// Presents and tracks detached popover windows — the "open in a window" button
/// every popover carries.
///
/// Two jobs. First, window lifetime: several windows at once (the point is to
/// watch a few things side by side across monitors), each retained until closed,
/// with re-detaching the same row focusing the window that already exists rather
/// than stacking duplicates. That half is `DebugWindowManager`'s shape, kept
/// deliberately identical down to the close-observer token ownership.
///
/// Second, and the actual feature: keeping them live. `StatusItemController`
/// hands every fresh parse to `update(pluginName:body:)`, which re-resolves each
/// open window's path and pushes the new values into its model. A window whose
/// row has vanished is marked stale rather than silently freezing.
@MainActor
final class DetachedPopoverWindows {
    static let shared = DetachedPopoverWindows()

    private var windows: [DetachedPopoverKey: NSWindow] = [:]
    private var models: [DetachedPopoverKey: DetachedPopoverModel] = [:]
    /// Close-observer tokens, keyed like `windows`. Owned here (manager state)
    /// rather than captured by the observer closure — same strict-concurrency
    /// reasoning as `DebugWindowManager`, and kept identical in shape.
    private var observerTokens: [DetachedPopoverKey: NSObjectProtocol] = [:]
    /// The most recent body per plugin, so a detach can locate the clicked row
    /// without the click path having to carry its address around.
    private var bodies: [String: [MenuNode]] = [:]
    /// Running cascade origin, so each new window steps down-right of the last.
    /// `.zero` makes the first `cascadeTopLeft(from:)` a no-op, which is the
    /// documented way to seed it.
    private var cascadePoint: NSPoint = .zero

    init() {}

    // MARK: - Detaching

    /// Opens (or focuses) a window watching `item` in `pluginName`'s menu.
    ///
    /// Returns `false` when the row can't be located in the plugin's current
    /// body — the caller should leave the popover alone rather than open a
    /// window that could never update.
    /// `onCommit` re-invokes a detached `toggle=`/`slider=`. It is handed the
    /// row as it stands *now*, not as it stood when the window was torn off, so
    /// a detached control runs the command the plugin currently declares.
    @discardableResult
    func detach(
        pluginName: String,
        item: MenuItem,
        onCommit: @escaping @MainActor (Double, MenuItem) -> Void = { _, _ in }
    ) -> Bool {
        guard let content = Self.content(of: item) else { return false }
        guard let body = bodies[pluginName],
              let path = MenuItemLocator.path(of: item, in: body) else { return false }

        let key = DetachedPopoverKey(pluginName: pluginName, path: path)
        if let existing = windows[key] {
            models[key]?.update(title: item.text, content: content)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        let model = DetachedPopoverModel(pluginName: pluginName, title: item.text, content: content) { [weak self] value in
            // Resolve the row again at commit time — the window may have been
            // open across many refreshes since it was torn off.
            guard let self, let body = self.bodies[pluginName],
                  let current = MenuItemLocator.item(at: path, in: body) else { return }
            onCommit(value, current)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: DetachedPopoverView(model: model)))
        window.title = Self.windowTitle(row: item.text, plugin: pluginName)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Set an explicit size rather than inheriting the hosting controller's
        // fitting size: the view fills its window (so a resize is useful), which
        // makes "fits" ambiguous. A legend row per segment makes charts taller.
        window.setContentSize(Self.initialSize(for: content))
        // Watching a value while working in another app is the whole use case,
        // so the window floats instead of sinking behind the frontmost app.
        window.level = .floating
        // Cascade rather than stack: opening three of these to watch side by
        // side is the point, and three windows centred on top of each other
        // would look like one.
        window.center()
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        windows[key] = window
        models[key] = model

        // Clear the entry when the window closes *any* way, including the
        // title-bar button — otherwise the key stays tracked forever and
        // re-detaching that row would focus a window the user already dismissed.
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose(key) }
        }
        observerTokens[key] = token

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// A single-line window title. Row text is plugin-supplied and may contain
    /// the newlines the format's `\n` escape produces, which a title bar renders
    /// as stray glyphs.
    static func windowTitle(row: String, plugin: String) -> String {
        let flattened = row
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return plugin }
        let clipped = flattened.count > 60 ? flattened.prefix(60) + "…" : flattened[...]
        return "\(clipped) — \(plugin)"
    }

    private static func initialSize(for content: DetachedPopoverContent) -> NSSize {
        switch content {
        case .sparkline:
            return NSSize(width: 320, height: 200)
        case .chart(let chart):
            return NSSize(width: 340, height: 250 + CGFloat(chart.values.count) * 17)
        case .control:
            return NSSize(width: 300, height: 150)
        }
    }

    /// Whether `item` has anything a detached window could show. Used by the
    /// popover host to decide whether to offer the button at all.
    static func isDetachable(_ item: MenuItem) -> Bool {
        content(of: item) != nil
    }

    private static func content(of item: MenuItem) -> DetachedPopoverContent? {
        // Mirrors `AppActionDispatcher`'s dispatch order exactly, so detaching
        // always reproduces the popover the row actually opened. A row carrying
        // both a control and a chart opens the control, so that is what it
        // detaches as — the button must never swap one surface for another.
        if let control = item.params.control { return .control(control) }
        if let series = item.params.sparkline, !series.isEmpty { return .sparkline(series) }
        if let chart = item.params.swiftbar.chart { return .chart(chart) }
        return nil
    }

    // MARK: - Liveness

    /// Records a plugin's freshly parsed dropdown and refreshes every window
    /// watching it. Called from `StatusItemController.render` — the one place
    /// new output reaches the UI.
    func update(pluginName: String, body: [MenuNode]) {
        bodies[pluginName] = body
        for (key, model) in models where key.pluginName == pluginName {
            guard let item = MenuItemLocator.item(at: key.path, in: body),
                  let content = Self.content(of: item) else {
                // The row is gone, or no longer opens a popover. Keep the last
                // value on screen but stop implying it is current.
                model.markStale()
                continue
            }
            model.update(title: item.text, content: content)
        }
    }

    /// Drops a plugin's cached body and marks its windows stale — used when a
    /// plugin is disabled or removed, so its windows don't keep advertising a
    /// value nothing is producing any more.
    func pluginWentAway(pluginName: String) {
        bodies[pluginName] = nil
        for (key, model) in models where key.pluginName == pluginName {
            model.markStale()
        }
    }

    /// Evicts the closed window and unregisters its close observer — a leftover
    /// registration (and the model its block retains) would otherwise accumulate
    /// once per window ever opened.
    private func windowWillClose(_ key: DetachedPopoverKey) {
        windows[key] = nil
        models[key] = nil
        if let token = observerTokens.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
