import AppKit
import SwiftUI

/// Presents the single consolidated Vee window (`LibraryView`) — the sidebar
/// window that replaces the separate Plugin Manager and Preferences windows
/// (see `docs/design/ui-consolidation.md`). Reopening focuses the existing
/// window and swaps in a fresh model, jumping to the requested section.
@MainActor
public final class LibraryWindow {
    public static let shared = LibraryWindow()

    private var window: NSWindow?

    /// Whether the consolidated window is currently on screen — lets the app
    /// skip a "look at Discover" nudge the user is already looking at.
    public var isVisible: Bool { window?.isVisible ?? false }

    public init() {}

    public func show(model: LibraryModel) {
        let view = LibraryView(model: model)
        if let window {
            (window.contentViewController as? NSHostingController<LibraryView>)?.rootView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Vee"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 580))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
