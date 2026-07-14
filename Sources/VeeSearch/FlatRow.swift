import Foundation
import VeePluginFormat

/// One activatable menu item, lifted out of the (possibly deeply nested) menu
/// tree into a flat, searchable row. Produced by `MenuFlattener.flatten`.
///
/// The row keeps the *original* `MenuItem` — with its full `LineParams` — so the
/// UI can fire it through the existing `MenuActionHandling.perform(_:)` with no
/// parallel action model: href / shell / shortcut / refresh / webview and the
/// toggle/slider/sparkline popovers all dispatch exactly as they do from a menu.
///
/// `title` and `haystack` are pre-folded (case-, diacritic-, width-insensitive)
/// so matching is allocation-light and locale-stable per keystroke.
public struct FlatRow: Equatable, Sendable {
    /// The original leaf/parent item — the source of truth for activation.
    public let item: MenuItem
    /// Ancestor group titles, outermost first, for the breadcrumb (`a › b › c`).
    public let path: [String]
    /// Folded item text — the primary rank target ("prefer matches in the item").
    public let title: String
    /// Folded item text + ancestor titles — the inclusion match target, so
    /// typing a group name surfaces its children.
    public let haystack: String

    public init(item: MenuItem, path: [String], title: String, haystack: String) {
        self.item = item
        self.path = path
        self.title = title
        self.haystack = haystack
    }

    /// The breadcrumb string for display, e.g. `orders › Epics`.
    public var breadcrumb: String { path.joined(separator: " › ") }

    /// Returns a copy of this row with `pluginName` prepended to the breadcrumb
    /// path. Used when aggregating rows across every enabled plugin into one
    /// cross-plugin search panel, so (a) the panel shows which plugin a row
    /// belongs to and (b) the plugin name itself becomes fuzzy-searchable —
    /// re-folded into `haystack` exactly like any other ancestor group.
    public func prefixed(with pluginName: String) -> FlatRow {
        let newPath = [pluginName] + path
        let newHaystack = SearchText.fold(([item.text] + newPath).joined(separator: " "))
        return FlatRow(item: item, path: newPath, title: title, haystack: newHaystack)
    }
}

/// A row paired with its match score for a given query (higher is better).
public struct ScoredRow: Equatable, Sendable {
    public let row: FlatRow
    public let score: Int

    public init(row: FlatRow, score: Int) {
        self.row = row
        self.score = score
    }
}
