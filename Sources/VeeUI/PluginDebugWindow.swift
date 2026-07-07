import AppKit
import SwiftUI

/// Presents and tracks per-plugin debug windows. Reopening a plugin's console
/// focuses the existing window (which keeps updating live as it re-runs).
@MainActor
public final class DebugWindowManager {
    public static let shared = DebugWindowManager()

    private var windows: [String: NSWindow] = [:]

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
        // dead, output frozen) until relaunch. The token is captured so the
        // handler can unregister itself; see SettingsWindowManager.show.
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows[pluginID] = nil
                if let token { NotificationCenter.default.removeObserver(token) }
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
