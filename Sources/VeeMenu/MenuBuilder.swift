import AppKit
import VeePluginFormat

/// Converts a parsed dropdown (`[MenuNode]`) into an `NSMenu`. Selectable leaf
/// items are wired to a `MenuActionTarget`; submenu parents open their submenu.
@MainActor
public enum MenuBuilder {
    public static func build(_ nodes: [MenuNode], target: MenuActionTarget) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, nodes: nodes, target: target)
        return menu
    }

    private static func fill(_ menu: NSMenu, nodes: [MenuNode], target: MenuActionTarget) {
        for node in nodes {
            switch node {
            case .separator:
                menu.addItem(.separator())
            case .item(let item):
                menu.addItem(makeItem(item, target: target))
                if let alternate = item.alternate {
                    menu.addItem(makeItem(alternate, target: target, isAlternate: true))
                }
            }
        }
    }

    private static func makeItem(_ item: MenuItem, target: MenuActionTarget, isAlternate: Bool = false) -> NSMenuItem {
        let menuItem = NSMenuItem()
        menuItem.attributedTitle = AttributedTitleFactory.make(
            text: item.text, params: item.params, ansiRuns: item.ansiRuns,
            defaultFont: NSFont.menuFont(ofSize: 0)
        )
        menuItem.image = SymbolImageFactory.image(for: item.params)
        menuItem.toolTip = item.params.swiftbar.tooltip
        menuItem.isEnabled = !(item.params.disabled ?? false)
        if item.params.swiftbar.checked == true { menuItem.state = .on }

        if isAlternate {
            menuItem.isAlternate = true
            menuItem.keyEquivalentModifierMask = .option
        }

        if !item.submenu.isEmpty {
            menuItem.submenu = build(item.submenu, target: target)
        } else if isActionable(item) {
            menuItem.representedObject = MenuItemBox(item)
            menuItem.target = target
            menuItem.action = target.action
        }
        return menuItem
    }

    /// A leaf item is clickable if it opens a URL, runs a shell command, or
    /// requests a refresh. Purely-decorative lines stay inert.
    private static func isActionable(_ item: MenuItem) -> Bool {
        item.params.href != nil || item.params.shell != nil || item.params.refresh == true
    }
}
