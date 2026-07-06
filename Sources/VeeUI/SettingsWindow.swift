import AppKit
import SwiftUI

/// Presents and tracks per-plugin settings windows, hosting the SwiftUI form in
/// an `NSWindow`. Reopening a plugin's settings focuses the existing window.
@MainActor
public final class SettingsWindowManager {
    public static let shared = SettingsWindowManager()

    private var windows: [String: NSWindow] = [:]

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
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows[pluginID] = nil }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close(_ pluginID: String) {
        // Triggers willCloseNotification, which clears the entry.
        windows[pluginID]?.close()
    }
}
