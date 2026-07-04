import AppKit
import SwiftUI

/// Presents the single plugin-browser window.
@MainActor
public final class PluginBrowserWindow {
    public static let shared = PluginBrowserWindow()

    private var window: NSWindow?

    public init() {}

    public func show(model: PluginBrowserModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: PluginBrowserView(model: model)))
        window.title = "Vee — Discover Plugins"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
