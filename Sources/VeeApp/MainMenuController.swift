import AppKit
import VeeCore

/// The always-present "Vee" status item hosting global controls (plugin manager,
/// refresh all, launch at login, quit). Per-plugin status items sit alongside it.
@MainActor
final class MainMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onManager: () -> Void
    private let onDiscover: () -> Void
    private let onPreferences: () -> Void
    private let onRefreshAll: () -> Void
    private let onOpenFolder: () -> Void
    private var loginItem: NSMenuItem!

    init(onManager: @escaping () -> Void, onDiscover: @escaping () -> Void, onPreferences: @escaping () -> Void, onRefreshAll: @escaping () -> Void, onOpenFolder: @escaping () -> Void) {
        self.onManager = onManager
        self.onDiscover = onDiscover
        self.onPreferences = onPreferences
        self.onRefreshAll = onRefreshAll
        self.onOpenFolder = onOpenFolder
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "v.circle.fill", accessibilityDescription: "Vee")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(item("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(item("Plugin Manager…", #selector(manage), key: "m"))
        menu.addItem(item("Discover Plugins…", #selector(discover), key: "d"))
        menu.addItem(item("Refresh All Plugins", #selector(refreshAll), key: "r"))
        menu.addItem(.separator())
        loginItem = item("Launch Vee at Login", #selector(toggleLogin), key: "")
        menu.addItem(loginItem)
        menu.addItem(item("Open Plugins Folder…", #selector(openFolder), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit Vee", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func openPreferences() { onPreferences() }
    @objc private func manage() { onManager() }
    @objc private func discover() { onDiscover() }
    @objc private func refreshAll() { onRefreshAll() }
    @objc private func openFolder() { onOpenFolder() }
    @objc private func toggleLogin() { LoginItemManager.setEnabled(!LoginItemManager.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }

    func remove() { NSStatusBar.system.removeStatusItem(statusItem) }
}
