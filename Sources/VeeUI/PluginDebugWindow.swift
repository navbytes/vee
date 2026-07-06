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

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
