import AppKit
import SwiftUI

/// Presents the single plugin-manager window.
@MainActor
public final class PluginManagerWindow {
    public static let shared = PluginManagerWindow()

    private var window: NSWindow?

    public init() {}

    public func show(model: PluginManagerModel) {
        if let window {
            (window.contentViewController as? NSHostingController<PluginManagerView>)?.rootView = PluginManagerView(model: model)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: PluginManagerView(model: model)))
        window.title = "Vee — Plugins"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
