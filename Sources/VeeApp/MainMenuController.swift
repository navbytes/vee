import AppKit
import VeeCore

/// Vee's global controls (plugin manager, refresh all, launch at login, quit)
/// and the `@objc` target behind them.
///
/// It owns no status item of its own. There is exactly one Vee icon, always
/// present — `CompactMenuBarController.shared` — and it hosts these rows as a
/// footer beneath whatever plugins are folded into it. `buildAppItems` is the
/// one seam those rows are built from, so this controller's own `menu` (built
/// for tests, and for any surface that wants the rows standalone) can never
/// drift from what the menu bar actually shows.
@MainActor
final class MainMenuController: NSObject, NSMenuDelegate {
    private let onManager: () -> Void
    private let onDiscover: () -> Void
    private let onPreferences: () -> Void
    private let onRefreshAll: () -> Void
    private let onOpenFolder: () -> Void
    private var loginItem: NSMenuItem!

    /// This controller's own copy of the rows — built unconditionally so a test
    /// can inspect their content and fire their callbacks without any status
    /// item existing.
    private(set) var menu = NSMenu()

    init(onManager: @escaping () -> Void, onDiscover: @escaping () -> Void, onPreferences: @escaping () -> Void, onRefreshAll: @escaping () -> Void, onOpenFolder: @escaping () -> Void, attachesStatusItem _: Bool = true) {
        self.onManager = onManager
        self.onDiscover = onDiscover
        self.onPreferences = onPreferences
        self.onRefreshAll = onRefreshAll
        self.onOpenFolder = onOpenFolder
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        loginItem = Self.buildAppItems(in: menu, target: self)
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Builds the standard "Vee" app-controls rows (Preferences/Plugin
    /// Manager/Discover/Refresh All/Launch at Login/Open
    /// Plugins Folder/Quit) into `menu`, targeting `target` for every row's
    /// action. The one place these rows are built — used both by this
    /// controller's own standalone menu (`init`, above) and by
    /// `CompactMenuBarController.installFooter`, so the two surfaces can never
    /// duplicate or drift out of sync on titles, key equivalents, or callbacks.
    /// Returns the "Launch Vee at Login" row so the caller can keep its
    /// checkmark fresh (see `menuNeedsUpdate`).
    @discardableResult
    static func buildAppItems(in menu: NSMenu, target: MainMenuController) -> NSMenuItem {
        menu.addItem(target.item("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(target.item("Plugin Manager…", #selector(manage), key: "m"))
        menu.addItem(target.item("Discover Plugins…", #selector(discover), key: "d"))
        menu.addItem(target.item("Refresh All Plugins", #selector(refreshAll), key: "r"))
        // Every open detached window, and a way back to each. Added here rather
        // than in either caller so this controller's own menu and the home
        // item's footer get it from the same seam, like every other row.
        menu.addItem(DetachedWindowsMenu.shared.makeItem())
        menu.addItem(.separator())
        let loginItem = target.item("Launch Vee at Login", #selector(toggleLogin), key: "")
        menu.addItem(loginItem)
        menu.addItem(target.item("Open Plugins Folder…", #selector(openFolder), key: ""))
        menu.addItem(.separator())
        menu.addItem(target.item("Quit Vee", #selector(quit), key: "q"))
        return loginItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        DetachedWindowsMenu.shared.refreshVisibility()
    }

    @objc private func openPreferences() { onPreferences() }
    @objc private func manage() { onManager() }
    @objc private func discover() { onDiscover() }
    @objc private func refreshAll() { onRefreshAll() }
    @objc private func openFolder() { onOpenFolder() }
    @objc private func toggleLogin() { LoginItemManager.setEnabled(!LoginItemManager.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }

}
