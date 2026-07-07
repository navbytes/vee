import AppKit
import SwiftUI

/// Presents and tracks per-plugin debug windows. Reopening a plugin's console
/// focuses the existing window (which keeps updating live as it re-runs).
@MainActor
public final class DebugWindowManager {
    public static let shared = DebugWindowManager()

    private var windows: [String: NSWindow] = [:]
    /// Close-observer tokens, keyed like `windows`. Owned here (manager state)
    /// rather than captured by the observer closure — see SettingsWindowManager
    /// for the strict-concurrency reasoning; the two are kept identical in shape.
    private var observerTokens: [String: NSObjectProtocol] = [:]

    public init() {}

    public func show(pluginID: String, model: PluginDebugModel) {
        if let existing = windows[pluginID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: PluginDebugView(model: model)))
        window.title = "\(model.pluginName) — Debug"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        windows[pluginID] = window

        // Clear the entry when the window is closed *any* way — including the
        // title-bar close button. Without this, reload() swapping coordinators
        // leaves a still-tracked window bound to a deallocated one ("Run again"
        // dead, output frozen) until relaunch.
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

    /// Evicts the closed window and unregisters its close observer — a
    /// leftover registration (and the state its block retains) would otherwise
    /// accumulate once per debug window ever opened.
    private func windowWillClose(_ pluginID: String) {
        windows[pluginID] = nil
        if let token = observerTokens.removeValue(forKey: pluginID) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
