import AppKit
import VeeCore

/// The always-present "Vee" status item hosting global controls (plugin manager,
/// refresh all, launch at login, quit). Per-plugin status items sit alongside it
/// in standalone mode.
///
/// Issue #71 follow-up ("one icon total" in compact mode): while
/// `AppPreferences.compactMenuBar` is on, this controller's own item is hidden
/// (`setVisible(false)`, driven by `AppController`'s mode-change wiring) and its
/// rows fold into `CompactMenuBarController`'s shared icon as a footer instead
/// (`buildAppItems`, below) — the one seam both surfaces build their app-control
/// rows from, so the two can never drift apart on titles/keys/callbacks.
@MainActor
final class MainMenuController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let onManager: () -> Void
    private let onDiscover: () -> Void
    private let onPreferences: () -> Void
    private let onRefreshAll: () -> Void
    private let onSearchAll: () -> Void
    private let onOpenFolder: () -> Void
    private var loginItem: NSMenuItem!

    /// This controller's own standalone menu — built unconditionally (even
    /// under `attachesStatusItem: false`) so a test can inspect its content and
    /// fire its callbacks without ever constructing a real status item.
    private(set) var menu = NSMenu()

    /// Skips ever touching `NSStatusBar` — the same hazard/seam
    /// `CompactMenuBarController.attachesStatusItem` guards against:
    /// constructing a real `NSStatusItem` needs a live `NSApplication`, unsafe
    /// to trigger from a unit test.
    private let attachesStatusItem: Bool

    /// Plain, directly testable mirror of `statusItem?.isVisible` (a test never
    /// has a real status item to read it off) — hidden while compact mode folds
    /// this controller's rows under the shared compact icon instead. Defaults
    /// to visible, matching the app always showing its icon prior to #71.
    private(set) var isVisible = true

    init(onManager: @escaping () -> Void, onDiscover: @escaping () -> Void, onPreferences: @escaping () -> Void, onRefreshAll: @escaping () -> Void, onSearchAll: @escaping () -> Void, onOpenFolder: @escaping () -> Void, attachesStatusItem: Bool = true) {
        self.onManager = onManager
        self.onDiscover = onDiscover
        self.onPreferences = onPreferences
        self.onRefreshAll = onRefreshAll
        self.onSearchAll = onSearchAll
        self.onOpenFolder = onOpenFolder
        self.attachesStatusItem = attachesStatusItem
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        loginItem = Self.buildAppItems(in: menu, target: self)

        guard attachesStatusItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "v.circle.fill", accessibilityDescription: "Vee")
            image?.isTemplate = true
            button.image = image
        }
        item.menu = menu
        statusItem = item
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Builds the standard "Vee" app-controls rows (Preferences/Plugin
    /// Manager/Discover/Refresh All/Search All Plugins/Launch at Login/Open
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
        // Cross-plugin "search everything" panel (docs/_content/roadmap.md's
        // parked slice): fuzzy-searches every enabled plugin's current menu at
        // once, not just one plugin's — see `AppController.openSearchAllPanel()`.
        menu.addItem(target.item("Search All Plugins…", #selector(searchAll), key: "f"))
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
    }

    @objc private func openPreferences() { onPreferences() }
    @objc private func manage() { onManager() }
    @objc private func discover() { onDiscover() }
    @objc private func refreshAll() { onRefreshAll() }
    @objc private func searchAll() { onSearchAll() }
    @objc private func openFolder() { onOpenFolder() }
    @objc private func toggleLogin() { LoginItemManager.setEnabled(!LoginItemManager.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Shows/hides this controller's own status item — hidden while compact
    /// mode folds its rows into the shared compact icon's footer instead
    /// (`AppController`'s mode-change wiring), shown again when compact mode
    /// turns off. `isVisible` always tracks the request, even under
    /// `attachesStatusItem: false` (tests), so the intent is directly
    /// assertable with no real status item involved.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        statusItem?.isVisible = visible
    }

    func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
