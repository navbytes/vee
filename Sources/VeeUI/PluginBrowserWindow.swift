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
            // Swap in the fresh model — otherwise a new store/changed plugins
            // directory never takes effect after the first open, and installs
            // would keep targeting the OLD directory.
            (window.contentViewController as? NSHostingController<PluginBrowserView>)?.rootView = PluginBrowserView(model: model)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: PluginBrowserView(model: model)))
        window.title = "Vee — Discover Plugins"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
