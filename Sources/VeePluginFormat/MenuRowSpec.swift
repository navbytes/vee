import Foundation

/// The display graphic a menu row draws inline: a `progress=` gauge, a
/// `sparkline=` trend, or a `pie=`/`donut=`/`stackedbar=` share chart.
///
/// A live `toggle=`/`slider=` control is deliberately **not** a case here. Every
/// case below is something any surface can draw; a control is not — an `NSMenu`
/// row cannot host one, so the menu bar draws the display graphic and opens the
/// control on click while a window draws the control in place. That difference
/// is a property of the presentation, and `MenuRowSpec` exposes the control
/// separately (`control`) so each surface can make it without either surface
/// re-deciding which *graphic* a row carries.
public enum MenuAccessory: Equatable, Sendable {
    case progress(ProgressParams, tint: VeeColor?)
    case sparkline([Double], style: SparklineStyle, tint: VeeColor?)
    case chart(ChartParams)
}

/// One row of a plugin's menu with every presentation decision already made.
///
/// This is the single answer to "what is this row?" that every surface reads —
/// the AppKit dropdown (`VeeMenu.MenuBuilder`) and the SwiftUI window/panel
/// (`VeeUI`/`VeeApp`) alike. It lives in `VeePluginFormat` rather than in either
/// renderer because those two modules are siblings and cannot see each other
/// (`VeeUI` does not depend on `VeeMenu`); the module they share is the only
/// place a genuinely shared decision can live. That is the same reason
/// `ProgressParams.defaultWidth` already lives here.
///
/// Deliberately Foundation-only, carrying **decisions, not pixels**. Resolving
/// text into an `NSAttributedString` and an icon into an `NSImage` stays in
/// `AttributedTitleFactory` / `SymbolImageFactory`, which both renderers already
/// call; pulling those types down here would drag AppKit into the pure parser.
/// The split is: this type decides *what is true* about a row, those factories
/// decide *how it looks*, and neither renderer decides anything.
public struct MenuRowSpec: Equatable, Sendable {
    /// The originating item — the source of truth for activation, and what the
    /// shared title/icon factories are handed. Kept whole so a surface fires the
    /// row through `MenuActionHandling.perform(_:)` with no parallel action
    /// model.
    public var item: MenuItem

    /// `header=true`: a non-interactive section title. Nothing else on the row
    /// applies — AppKit renders it via `NSMenuItem.sectionHeader(title:)`, which
    /// is title-only, and a header's submenu is never part of the dropdown.
    public var isHeader: Bool

    /// `disabled=true` inverted. A disabled row is visible but never acts.
    public var isEnabled: Bool

    /// `checked=true`: the plugin's own "this one is selected" marker.
    public var isChecked: Bool

    /// `tooltip=`: the row's hover text, if any.
    public var tooltip: String?

    /// Whether activating this row does anything.
    ///
    /// The single definition, mirroring `AppActionDispatcher.perform`'s dispatch
    /// set. A row is actionable iff it is enabled, has no children of its own,
    /// and declares something the dispatcher acts on. Previously decided
    /// independently in `MenuBuilder.isActionable` and
    /// `MenuFlattener.isActionable`, kept in agreement only by a comment.
    public var isActionable: Bool

    /// The display graphic drawn inline, if any.
    public var accessory: MenuAccessory?

    /// The live control this row carries, if any. Separate from `accessory`
    /// because whether it is drawn inline is the presentation's call — see
    /// `MenuAccessory`.
    public var control: PluginControl?

    /// `accessory=leading`: the graphic sits before the label instead of after.
    public var accessoryLeading: Bool

    /// `key=`: the raw key-equivalent string, for surfaces that can bind one
    /// (only an open `NSMenu` can). Left unparsed here — parsing it needs
    /// AppKit's modifier masks.
    public var keyEquivalent: String?

    /// `alternate=true`: this row replaces its predecessor while ⌥ is held. A
    /// surface with no menu tracking may present it as an ordinary row instead.
    public var isAlternate: Bool

    /// This row's own nested rows, after `dropdown=false` children are dropped.
    /// What a surface renders beneath the row.
    public var children: [MenuTreeNode]

    /// Whether the item declared *any* children before filtering.
    ///
    /// Distinct from `children.isEmpty` on purpose: a row whose children are all
    /// `dropdown=false` declares a submenu that renders empty. Both renderers
    /// have always keyed the submenu-wins-over-action rule off the unfiltered
    /// declaration, so that row is inert with an empty submenu rather than
    /// becoming clickable. Preserved here rather than quietly corrected.
    public var hasSubmenu: Bool

    public init(
        item: MenuItem,
        isHeader: Bool = false,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        tooltip: String? = nil,
        isActionable: Bool = false,
        accessory: MenuAccessory? = nil,
        control: PluginControl? = nil,
        accessoryLeading: Bool = false,
        keyEquivalent: String? = nil,
        isAlternate: Bool = false,
        children: [MenuTreeNode] = [],
        hasSubmenu: Bool = false
    ) {
        self.item = item
        self.isHeader = isHeader
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.tooltip = tooltip
        self.isActionable = isActionable
        self.accessory = accessory
        self.control = control
        self.accessoryLeading = accessoryLeading
        self.keyEquivalent = keyEquivalent
        self.isAlternate = isAlternate
        self.children = children
        self.hasSubmenu = hasSubmenu
    }

    /// The row's text, for surfaces that only need the label.
    public var text: String { item.text }
}

/// A node in a resolved menu: a row, or a divider between groups.
///
/// `indirect` for the same reason `MenuNode` is — a row holds children, which
/// hold rows.
public indirect enum MenuTreeNode: Equatable, Sendable {
    case row(MenuRowSpec)
    case separator
}

/// Resolves a parsed dropdown (`[MenuNode]`) into the decided form every surface
/// renders (`[MenuTreeNode]`).
///
/// Every question a renderer used to answer for itself is answered exactly once
/// here: which nodes become rows at all, whether a row acts, which display
/// graphic it carries, and where an `alternate=` sibling sits. Pure, so all of
/// it is unit-testable without an `NSMenu` or a running app.
public enum MenuTree {
    /// Resolves `nodes` into rows, preserving the plugin's authored order and
    /// structure. Nothing is collapsed, inserted, or repaired — a surface shows
    /// separators and headers exactly where the plugin put them.
    public static func build(_ nodes: [MenuNode]) -> [MenuTreeNode] {
        var result: [MenuTreeNode] = []
        for node in nodes {
            switch node {
            case .separator:
                result.append(.separator)
            case .item(let item):
                // `dropdown=false` marks a menu-bar-only line: it is not part of
                // any dropdown surface, and its alternate goes with it.
                guard item.params.dropdown != false else { continue }
                result.append(.row(row(for: item)))
                // `alternate=true` is a *sibling* of the row it replaces, added
                // immediately after it at the same level — not a child. AppKit
                // shows it in place of its predecessor while ⌥ is held.
                //
                // It inherits the primary's `key=`. AppKit swaps the two only
                // when they carry the **same key equivalent** and differ in
                // modifier mask; give the alternate its own (or none, where the
                // primary declared one) and the pair simply renders as two
                // ordinary rows with ⌥ doing nothing. An alternate's own `key=`
                // cannot be honoured for the same reason, so the primary's wins.
                if let alternate = item.alternate {
                    result.append(.row(row(for: alternate, isAlternate: true, inheritedKey: item.params.key)))
                }
            }
        }
        return result
    }

    /// Resolves one item into its row.
    ///
    /// A `header=true` item returns early with nothing else resolved: AppKit's
    /// native section header is title-only ("non-interactive and do not perform
    /// an action"), and its submenu is never part of the dropdown, so neither is
    /// walked here.
    public static func row(
        for item: MenuItem,
        isAlternate: Bool = false,
        inheritedKey: String? = nil
    ) -> MenuRowSpec {
        if item.params.swiftbar.header == true {
            return MenuRowSpec(item: item, isHeader: true, isEnabled: false, isAlternate: isAlternate)
        }

        let children = build(item.submenu)
        let hasSubmenu = !item.submenu.isEmpty
        let enabled = !(item.params.disabled ?? false)
        return MenuRowSpec(
            item: item,
            isEnabled: enabled,
            isChecked: item.params.swiftbar.checked == true,
            tooltip: item.params.swiftbar.tooltip,
            // Children win over a command: a row with both opens its children
            // rather than running, so it must not act on any surface. Enabled
            // and childless are both required before the dispatch set is even
            // consulted. Keyed off the *declaration*, not the filtered result —
            // see `hasSubmenu`.
            isActionable: enabled && !hasSubmenu && dispatches(item),
            accessory: accessory(for: item.params),
            control: item.params.control,
            accessoryLeading: item.params.swiftbar.accessory == .leading,
            keyEquivalent: isAlternate ? inheritedKey : item.params.key,
            isAlternate: isAlternate,
            children: children,
            hasSubmenu: hasSubmenu
        )
    }

    /// Whether the action dispatcher would act on this item.
    ///
    /// Mirrors `AppActionDispatcher.perform`'s dispatch set, and is the **only**
    /// place that set is written down for rendering purposes. `progress=` is
    /// display-only (never dispatched), so it does not make a row actionable;
    /// `sparkline=` and a chart do, because clicking one opens its popover.
    public static func dispatches(_ item: MenuItem) -> Bool {
        let p = item.params
        if p.control != nil { return true }
        if p.shell != nil { return true }
        if p.swiftbar.webview != nil { return true }
        if p.sparkline != nil { return true }
        if p.swiftbar.chart != nil { return true }
        if p.href != nil { return true }
        if let shortcut = p.swiftbar.shortcut, !shortcut.isEmpty { return true }
        if p.refresh == true { return true }
        return false
    }

    /// The display graphic a row draws inline, or `nil` for a plain row.
    ///
    /// Precedence is oldest-param-first — progress, then sparkline, then chart —
    /// matching the order the dropdown has always drawn them in. A row declaring
    /// several shows exactly one, and shows the same one everywhere.
    public static func accessory(for params: LineParams) -> MenuAccessory? {
        if let progress = params.progress {
            return .progress(progress, tint: params.color)
        }
        if let series = params.sparkline, !series.isEmpty {
            return .sparkline(series, style: params.swiftbar.sparklineStyle ?? SparklineStyle(), tint: params.color)
        }
        if let chart = params.swiftbar.chart {
            return .chart(chart)
        }
        return nil
    }
}
