import AppKit
import SwiftUI

/// Presents and tracks per-plugin settings windows, hosting the SwiftUI form in
/// an `NSWindow`. Reopening a plugin's settings focuses the existing window.
@MainActor
public final class SettingsWindowManager {
    public static let shared = SettingsWindowManager()

    private var windows: [String: NSWindow] = [:]
    /// Close-observer tokens, keyed like `windows`. Owned here (manager state)
    /// rather than captured by the observer closure: a token local captured by
    /// the `@Sendable` notification closure is a non-Sendable value crossing
    /// isolation regions, which strict concurrency rejects as a data race.
    private var observerTokens: [String: NSObjectProtocol] = [:]

    public init() {}

    public func show(pluginID: String, model: PluginSettingsModel) {
        if let existing = windows[pluginID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PluginSettingsView(model: model) { [weak self] in self?.close(pluginID) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "\(model.pluginName) — Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        windows[pluginID] = window

        // Clear the entry when the window is closed *any* way — including the
        // title-bar close button, which bypasses `close(_:)`. Without this a
        // closed window is retained forever and reopening re-shows the stale one.
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose(pluginID) }
        }
        // Stored in manager state (not captured by the closure) so the handler
        // can unregister it. Ordering is safe: willClose can only fire on a
        // later main-runloop turn, so the token is always stored before the
        // handler could ever consume it.
        observerTokens[pluginID] = token

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close(_ pluginID: String) {
        // Triggers willCloseNotification, which clears the entry.
        windows[pluginID]?.close()
    }

    /// Evicts the closed window and unregisters its close observer — a
    /// leftover registration (and the state its block retains) would otherwise
    /// accumulate once per settings window ever opened.
    private func windowWillClose(_ pluginID: String) {
        windows[pluginID] = nil
        if let token = observerTokens.removeValue(forKey: pluginID) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
