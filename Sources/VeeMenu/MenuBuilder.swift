import AppKit
import VeePluginFormat

/// Emits an `NSMenu` from a resolved menu (`MenuTree`). Selectable leaf rows are
/// wired to a `MenuActionTarget`; rows with children open their submenu.
///
/// Deliberately decides **nothing**. Which nodes become rows, whether a row
/// acts, which inline graphic it carries, and where an `alternate=` sibling
/// sits are all settled in `VeePluginFormat.MenuTree` — the module `VeeUI`'s
/// SwiftUI rows read too, so the two surfaces cannot disagree about what a row
/// is. What remains here is AppKit assembly: turning decisions into
/// `NSMenuItem`s. The only `params` this file touches are the ones it hands
/// wholesale to the shared title/icon factories, which the SwiftUI rows call
/// with the same arguments.
@MainActor
public enum MenuBuilder {
    public static func build(_ nodes: [MenuNode], target: MenuActionTarget) -> NSMenu {
        // This file *is* the menu-bar dropdown, so `.menu` is its surface by
        // construction — there is no caller that could mean another one.
        emit(MenuTree.build(nodes, surface: .menu), target: target)
    }

    /// Builds a menu from already-resolved rows.
    public static func emit(_ nodes: [MenuTreeNode], target: MenuActionTarget) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, nodes: nodes, target: target)
        return menu
    }

    private static func fill(_ menu: NSMenu, nodes: [MenuTreeNode], target: MenuActionTarget) {
        for node in nodes {
            switch node {
            case .separator:
                menu.addItem(.separator())
            case .row(let row):
                menu.addItem(makeItem(row, target: target))
            }
        }
    }

    private static func makeItem(_ row: MenuRowSpec, target: MenuActionTarget) -> NSMenuItem {
        // A section header is title-only — AppKit's native section-header item
        // is non-interactive and carries none of the presentation below.
        if row.isHeader {
            return NSMenuItem.sectionHeader(title: row.text)
        }

        let item = row.item
        let menuItem = NSMenuItem()
        menuItem.attributedTitle = AttributedTitleFactory.make(
            text: item.text, params: item.params, ansiRuns: item.ansiRuns,
            defaultFont: NSFont.menuFont(ofSize: 0)
        )
        menuItem.image = SymbolImageFactory.image(for: item.params)
        menuItem.toolTip = row.tooltip
        menuItem.isEnabled = row.isEnabled
        if row.isChecked { menuItem.state = .on }

        // A row carrying a display graphic renders it as a custom row view.
        // These views are decorative (no click handling of their own), and the
        // row can still open a submenu or fire its own action, so this does not
        // return early — the wiring below applies exactly as it does to a plain
        // row. Note the menu bar draws the *graphic* even when the row also
        // carries a live control: an `NSMenu` row cannot host one, so the
        // control opens as a popover on click instead.
        if let accessory = row.accessory {
            menuItem.view = accessoryView(accessory, title: menuItem.attributedTitle ?? NSAttributedString(string: item.text), leading: row.accessoryLeading)
            menuItem.view?.toolTip = row.tooltip
        }

        if row.isAlternate {
            menuItem.isAlternate = true
            // AppKit swaps an alternate for its predecessor only when the two
            // carry the **same key equivalent** and differ in modifier mask. So
            // the alternate takes the primary's key (inherited in `MenuTree`)
            // and adds ⌥ to its modifiers; leaving the key empty while the
            // primary declared one renders both rows at once with ⌥ inert.
            if let key = row.keyEquivalent, let equivalent = KeyEquivalentParser.parse(key) {
                menuItem.keyEquivalent = equivalent.key
                // A primary that already declares ⌥ leaves the two masks equal
                // and therefore indistinguishable — a plugin-authoring mistake
                // AppKit gives us no way to resolve.
                menuItem.keyEquivalentModifierMask = equivalent.modifiers.union(.option)
            } else {
                menuItem.keyEquivalentModifierMask = .option
            }
        } else if let key = row.keyEquivalent, let equivalent = KeyEquivalentParser.parse(key) {
            // `key=`: a shortcut active while the menu is open.
            menuItem.keyEquivalent = equivalent.key
            menuItem.keyEquivalentModifierMask = equivalent.modifiers
        }

        if row.hasSubmenu {
            menuItem.submenu = emit(row.children, target: target)
        } else if row.isActionable {
            menuItem.representedObject = MenuItemBox(item)
            menuItem.target = target
            menuItem.action = target.action
        }
        return menuItem
    }

    /// The custom row view for a display graphic. Colors and dimensions come
    /// from the same places the SwiftUI rows read them, so a gauge or chart
    /// drawn here and the same one drawn in a window agree by construction.
    private static func accessoryView(_ accessory: MenuAccessory, title: NSAttributedString, leading: Bool) -> NSView {
        switch accessory {
        case .progress(let progress, let tint):
            return ProgressMenuItemView(
                title: title,
                fraction: progress.fraction,
                fillColor: tint.flatMap(ColorResolver.nsColor(for:)) ?? .controlAccentColor,
                trackColor: progress.trackColor.flatMap(ColorResolver.nsColor(for:))
                    ?? NSColor.tertiaryLabelColor.withAlphaComponent(0.25),
                barWidth: CGFloat(progress.effectiveWidth),
                barHeight: CGFloat(progress.effectiveHeight),
                leading: leading,
                fullWidth: progress.isFullWidth
            )
        case .sparkline(let values, let style, let tint):
            // `sparklinecolor=` wins, then the row's own `color=`, then the
            // accent — the same ladder `progress=` uses for its fill.
            return SparklineMenuItemView(
                title: title,
                values: values,
                lineColor: style.color.flatMap(ColorResolver.nsColor(for:))
                    ?? tint.flatMap(ColorResolver.nsColor(for:))
                    ?? .controlAccentColor,
                chartWidth: CGFloat(style.effectiveWidth),
                chartHeight: CGFloat(style.effectiveHeight),
                leading: leading,
                fullWidth: style.isFullWidth
            )
        case .chart(let chart):
            return CategoryChartMenuItemView(title: title, chart: chart, leading: leading)
        }
    }
}
