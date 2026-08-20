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
                // `dropdown=false` marks a menu-bar-only line; omit it from the
                // dropdown (its alternate goes with it).
                if item.params.dropdown == false { continue }
                menu.addItem(makeItem(item, target: target))
                if let alternate = item.alternate {
                    menu.addItem(makeItem(alternate, target: target, isAlternate: true))
                }
            }
        }
    }

    private static func makeItem(_ item: MenuItem, target: MenuActionTarget, isAlternate: Bool = false) -> NSMenuItem {
        // `header=true`: a first-class, non-interactive section-header row,
        // using AppKit's native section-header item (macOS 14+) instead of a
        // `disabled=true` line pretending to be one. Title only — none of the
        // interactive/visual params below apply to it (Apple: section headers
        // "are non-interactive and do not perform an action").
        if item.params.swiftbar.header == true {
            return NSMenuItem.sectionHeader(title: item.text)
        }

        let menuItem = NSMenuItem()
        menuItem.attributedTitle = AttributedTitleFactory.make(
            text: item.text, params: item.params, ansiRuns: item.ansiRuns,
            defaultFont: NSFont.menuFont(ofSize: 0)
        )
        menuItem.image = SymbolImageFactory.image(for: item.params)
        menuItem.toolTip = item.params.swiftbar.tooltip
        menuItem.isEnabled = !(item.params.disabled ?? false)
        if item.params.swiftbar.checked == true { menuItem.state = .on }

        // `progress=`/`sparkline=`: render an inline capsule gauge / chart as a
        // custom row view. Both views are decorative (no click handling of
        // their own — see ProgressMenuItemView/SparklineMenuItemView), but the
        // row can still carry a submenu or its own action (href=/shell=/…),
        // same as any other item, so fall through to the same submenu/action
        // wiring below instead of returning early. A row that sets both
        // renders the progress bar (it shipped first); sparkline='s
        // click-to-popover keeps working regardless, since the dispatcher
        // reads `params.sparkline`, not the row's view.
        let accessoryLeading = item.params.swiftbar.accessory == .leading
        if let progress = item.params.progress {
            let view = ProgressMenuItemView(
                title: menuItem.attributedTitle ?? NSAttributedString(string: item.text),
                fraction: progress.fraction,
                fillColor: item.params.color.flatMap(ColorResolver.nsColor(for:)) ?? .controlAccentColor,
                trackColor: progress.trackColor.flatMap(ColorResolver.nsColor(for:))
                    ?? NSColor.tertiaryLabelColor.withAlphaComponent(0.25),
                barWidth: progress.width.map { CGFloat($0) } ?? 120,
                barHeight: progress.height.map { CGFloat($0) } ?? 6,
                leading: accessoryLeading
            )
            view.toolTip = item.params.swiftbar.tooltip
            menuItem.view = view
        } else if let series = item.params.sparkline {
            let view = SparklineMenuItemView(
                title: menuItem.attributedTitle ?? NSAttributedString(string: item.text),
                values: series,
                lineColor: item.params.color.flatMap(ColorResolver.nsColor(for:)) ?? .controlAccentColor,
                leading: accessoryLeading
            )
            view.toolTip = item.params.swiftbar.tooltip
            menuItem.view = view
        }

        if isAlternate {
            menuItem.isAlternate = true
            menuItem.keyEquivalentModifierMask = .option
        } else if let key = item.params.key, let equivalent = KeyEquivalentParser.parse(key) {
            // `key=`: attach a keyboard shortcut, active while the menu is open.
            menuItem.keyEquivalent = equivalent.key
            menuItem.keyEquivalentModifierMask = equivalent.modifiers
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

    /// A leaf item is clickable if it opens a URL, runs a shell command, runs a
    /// macOS Shortcut, or requests a refresh. Purely-decorative lines stay inert.
    private static func isActionable(_ item: MenuItem) -> Bool {
        item.params.href != nil
            || item.params.shell != nil
            || item.params.refresh == true
            || item.params.swiftbar.shortcut?.isEmpty == false
            || item.params.swiftbar.webview != nil
            || item.params.sparkline != nil
            || item.params.control != nil
    }
}
