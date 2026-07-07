import Foundation
import VeePluginFormat

/// Flattens a plugin's nested menu tree into a flat list of activatable
/// `FlatRow`s, carrying each item's ancestor path for the breadcrumb. Pure and
/// AppKit-free, so it is fully unit-tested independent of any UI.
public enum MenuFlattener {
    /// Flattens `nodes` (a `ParsedOutput.body`) into activatable rows.
    public static func flatten(_ nodes: [MenuNode]) -> [FlatRow] {
        var rows: [FlatRow] = []
        walk(nodes, path: [], into: &rows)
        return rows
    }

    /// Whether activating this item does something. Mirrors the dispatch order in
    /// `AppActionDispatcher.perform` exactly — an item is a row iff the dispatcher
    /// would act on it — so nothing surfaces that would be a no-op on Enter, and
    /// nothing that *would* act is dropped. `progress=` is a display-only gauge
    /// (never dispatched), so it does not by itself make an item actionable.
    static func isActionable(_ item: MenuItem) -> Bool {
        let p = item.params
        if p.control != nil { return true }
        if p.shell != nil { return true }
        if p.swiftbar.webview != nil { return true }
        if p.sparkline != nil { return true }
        if p.href != nil { return true }
        if let shortcut = p.swiftbar.shortcut, !shortcut.isEmpty { return true }
        if p.refresh == true { return true }
        return false
    }

    private static func walk(_ nodes: [MenuNode], path: [String], into rows: inout [FlatRow]) {
        for node in nodes {
            guard case .item(let item) = node else { continue }   // separators contribute nothing

            let hasText = !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let disabled = item.params.disabled ?? false
            let menuBarOnly = item.params.dropdown == false        // dropdown=false → menu-bar only

            // Emit this item as a row when it is itself activatable and selectable
            // — even if it *also* has a submenu. A clickable parent (an item with
            // both `href=`/`shell=` and children) would otherwise have its own
            // action unreachable in the flattened view.
            if hasText, !disabled, !menuBarOnly, isActionable(item) {
                rows.append(makeRow(item, path: path))
            }

            // Always descend; a non-empty text becomes the next breadcrumb segment.
            // An empty-text group contributes no segment (no dangling ` › `).
            if !item.submenu.isEmpty {
                let childPath = hasText ? path + [item.text] : path
                walk(item.submenu, path: childPath, into: &rows)
            }
        }
    }

    private static func makeRow(_ item: MenuItem, path: [String]) -> FlatRow {
        let title = SearchText.fold(item.text)
        let haystack = SearchText.fold(([item.text] + path).joined(separator: " "))
        return FlatRow(item: item, path: path, title: title, haystack: haystack)
    }
}
