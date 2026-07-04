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

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close(_ pluginID: String) {
        windows[pluginID]?.close()
        windows[pluginID] = nil
    }
}
