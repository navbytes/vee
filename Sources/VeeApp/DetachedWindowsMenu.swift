import AppKit

/// The "Detached Windows" row and its submenu: every open detached window, and
/// a way back to each.
///
/// This is the feature's **guaranteed retrieval path**, not a convenience. Vee
/// runs as an accessory app (`LSUIElement`), so a window the user has unpinned
/// and then covered has no Dock icon to click and no App Exposé route back —
/// App Exposé is scoped to the frontmost application, so if the window is behind
/// Safari then Safari is frontmost and the gesture shows Safari's windows, not
/// Vee's. The menu bar is always reachable regardless of what is in front, so
/// this row always is too.
///
/// Built once and shared by both surfaces that render Vee's app controls — its
/// own status item and compact mode's folded footer — through
/// `MainMenuController.buildAppItems`, the single seam those two agree on.
/// The submenu fills itself on open (`menuNeedsUpdate`) so it never shows a
/// stale list, and the row hides entirely when nothing is open.
@MainActor
final class DetachedWindowsMenu: NSObject, NSMenuDelegate {
    static let shared = DetachedWindowsMenu()

    /// The rows handed out by `makeItem`, so visibility can be refreshed on
    /// whichever surface is opening. At most two exist (standalone + compact
    /// footer); rows whose menu has gone away are pruned as we go.
    private var items: [NSMenuItem] = []

    private var windows: DetachedPluginWindows { .shared }

    /// Builds the row. Starts hidden — `refreshVisibility` reveals it when a
    /// window exists, which every parent menu calls as it opens.
    func makeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Detached Windows", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Detached Windows")
        submenu.autoenablesItems = false
        submenu.delegate = self
        item.submenu = submenu
        item.isHidden = windows.isEmpty
        items.removeAll { $0.menu == nil }
        items.append(item)
        return item
    }

    /// Hides or shows every row according to whether anything is open. Called
    /// from each parent menu's `menuNeedsUpdate`, because a submenu's own
    /// delegate does not run until the user hovers it — by which point the row
    /// is already on screen.
    func refreshVisibility() {
        items.removeAll { $0.menu == nil }
        let hidden = windows.isEmpty
        for item in items { item.isHidden = hidden }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = windows.openPlugins
        // Nothing open means no rows at all — and the parent already hid this
        // whole row via `refreshVisibility`, so the bring-all action below needs
        // no empty-state guard of its own.
        guard !open.isEmpty else { return }
        // Top of the submenu, where macOS's own Window menu puts it: the
        // mouse-reachable twin of the app-level hotkey, and the only retrieval
        // that is one gesture rather than one per window.
        let bringAll = NSMenuItem(title: "Bring All to Front", action: #selector(focusAll), keyEquivalent: "")
        bringAll.target = self
        menu.addItem(bringAll)
        menu.addItem(.separator())
        for pluginName in open {
            // A stale window is still worth listing — it is showing the last
            // thing its plugin said, and finding it is exactly how the user
            // discovers the plugin stopped reporting.
            let title = windows.isStale(pluginName: pluginName) ? "\(pluginName) (stale)" : pluginName
            let item = NSMenuItem(title: title, action: #selector(focus(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pluginName
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let closeAll = NSMenuItem(title: "Close All", action: #selector(closeAll), keyEquivalent: "")
        closeAll.target = self
        menu.addItem(closeAll)
    }

    @objc private func focus(_ sender: NSMenuItem) {
        guard let pluginName = sender.representedObject as? String else { return }
        windows.focus(pluginName: pluginName)
    }

    @objc private func focusAll() {
        windows.focusAll()
    }

    @objc private func closeAll() {
        windows.closeAll()
    }
}
