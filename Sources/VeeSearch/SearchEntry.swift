import Foundation

/// One row surfaced by the search panel — a superset of `FlatRow` that keeps
/// the menu tree's structural furniture (`header=true` section titles,
/// separators) and non-actionable "sub-text" rows alongside the activatable
/// ones. `MenuFlattener.flatten`/`FlatRow` alone only ever kept the
/// selectable subset; the panel needs the full picture so it renders the same
/// structure the native dropdown does instead of silently dropping the rest.
public enum SearchEntry: Equatable, Sendable {
    /// A selectable, activatable row.
    case action(FlatRow)
    /// A visible, fuzzy-matchable row that does nothing on Enter — a disabled
    /// item or a plain sub-text line.
    case info(FlatRow)
    /// A section title (`header=true` item).
    case header(String)
    /// A divider between groups.
    case separator

    /// Returns a copy of this entry with `pluginName` prepended to its
    /// breadcrumb path — the `SearchEntry` counterpart of
    /// `FlatRow.prefixed(with:)`, used when aggregating every plugin's
    /// flattened menu into one cross-plugin panel. Headers/separators carry no
    /// breadcrumb, so they pass through unchanged.
    public func prefixed(with pluginName: String) -> SearchEntry {
        switch self {
        case .action(let row): return .action(row.prefixed(with: pluginName))
        case .info(let row): return .info(row.prefixed(with: pluginName))
        case .header, .separator: return self
        }
    }
}
