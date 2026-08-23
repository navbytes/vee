import Foundation
import VeePluginFormat

/// Flattens a plugin's nested menu tree into a flat list of activatable
/// `FlatRow`s, carrying each item's ancestor path for the breadcrumb. Pure and
/// AppKit-free, so it is fully unit-tested independent of any UI.
///
/// The app's menu surfaces no longer flatten anything — they render the
/// structure directly (`MenuTree`/`MenuTreeFilter`). This projection survives
/// for `vee search`, where a terminal has no tree to draw and a ranked list is
/// the right answer, and it is that subcommand's only remaining consumer.
public enum MenuFlattener {
    /// Flattens `nodes` (a `ParsedOutput.body`) into activatable rows only.
    public static func flatten(_ nodes: [MenuNode]) -> [FlatRow] {
        var rows: [FlatRow] = []
        walk(nodes, path: [], into: &rows)
        return rows
    }

    /// Whether activating this item does something.
    ///
    /// Delegates to `MenuTree.dispatches` — the single definition of the
    /// dispatch set, shared with the AppKit dropdown. This used to be a second
    /// copy kept in agreement with `MenuBuilder.isActionable` by a comment.
    static func isActionable(_ item: MenuItem) -> Bool {
        MenuTree.dispatches(item)
    }

    /// Depth-first walk (emission order matches descent order). A `header=true`
    /// item doesn't just emit its own title — it opens a *section* that
    /// "adopts" the following siblings at this level, as if the header were an
    /// extra ancestor group: their row path (breadcrumb + haystack) and any
    /// further descent both fold in the section title, so typing the section
    /// name surfaces its rows. The section resets at the next header or
    /// separator at the same level. `section` is a local to this call frame,
    /// so nested submenus always start their own tracking fresh.
    private static func walk(_ nodes: [MenuNode], path: [String], into rows: inout [FlatRow]) {
        var section: String?

        for node in nodes {
            guard case .item(let item) = node else {
                section = nil
                continue
            }

            let hasText = !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let effectivePath = section.map { path + [$0] } ?? path
            let childPath = hasText ? effectivePath + [item.text] : effectivePath

            // `dropdown=false` (menu-bar-only): invisible here — not even as a
            // section boundary — but still descends.
            if item.params.dropdown == false {
                if !item.submenu.isEmpty { walk(item.submenu, path: childPath, into: &rows) }
                continue
            }

            if item.params.swiftbar.header == true {
                // A header's submenu is never part of the dropdown, so it is
                // never walked here either.
                section = hasText ? item.text : nil   // opens (or, if titleless, just closes) scope for what follows
                continue
            }

            if hasText, isSelectable(item) { rows.append(makeRow(item, path: effectivePath)) }
            // Always descend; empty text contributes no breadcrumb segment.
            if !item.submenu.isEmpty { walk(item.submenu, path: childPath, into: &rows) }

            // `alternate=true` is a sibling of the row it replaces, not a
            // child — flatten it as a peer at the same level, right after the
            // subtree, so it is searchable and activatable rather than absent.
            if let alt = item.alternate {
                let hasAltText = !alt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasAltText, isSelectable(alt) { rows.append(makeRow(alt, path: effectivePath)) }
                if !alt.submenu.isEmpty {
                    let altChildPath = hasAltText ? effectivePath + [alt.text] : effectivePath
                    walk(alt.submenu, path: altChildPath, into: &rows)
                }
            }
        }
    }

    /// Selectable iff enabled, actionable, AND childless. A row with both
    /// children and a command opens its children natively rather than running,
    /// so a destructive command that never fires from the menu bar must not
    /// fire from here either.
    private static func isSelectable(_ item: MenuItem) -> Bool {
        let disabled = item.params.disabled ?? false
        return !disabled && item.submenu.isEmpty && isActionable(item)
    }

    private static func makeRow(_ item: MenuItem, path: [String]) -> FlatRow {
        let title = SearchText.fold(item.text)
        let haystack = SearchText.fold(([item.text] + path).joined(separator: " "))
        return FlatRow(item: item, path: path, title: title, haystack: haystack)
    }
}
