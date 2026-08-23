import Foundation
import VeePluginFormat

/// Flattens a plugin's nested menu tree into a flat list of activatable
/// `FlatRow`s, carrying each item's ancestor path for the breadcrumb. Pure and
/// AppKit-free, so it is fully unit-tested independent of any UI.
public enum MenuFlattener {
    /// Flattens `nodes` (a `ParsedOutput.body`) into activatable rows only. A
    /// thin filter over `flattenEntries`, kept for callers/tests that only
    /// ever wanted the selectable subset.
    public static func flatten(_ nodes: [MenuNode]) -> [FlatRow] {
        flattenEntries(nodes).compactMap {
            if case .action(let row) = $0 { return row }
            return nil
        }
    }

    /// Flattens `nodes` into every panel-visible entry — actionable rows,
    /// non-actionable "info" rows (sub-text, disabled items), section headers
    /// and separators — so the search panel can mirror the same structure the
    /// native dropdown renders instead of showing only the clickable subset.
    public static func flattenEntries(_ nodes: [MenuNode]) -> [SearchEntry] {
        var entries: [SearchEntry] = []
        walk(nodes, path: [], depth: 0, into: &entries)
        return normalized(entries)
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
    ///
    /// `depth` (0 = the top-level list) gates whether `.header`/`.separator`
    /// are appended as their own entries: a submenu opens as a *sibling*
    /// dropdown, not inline, so its furniture must not splice into the
    /// flat stream between top-level rows that visually surround it — only
    /// depth 0's own headers/separators become panel rows. Section-scope
    /// bookkeeping still runs at every depth regardless (a nested header
    /// still folds into its own level's breadcrumb, a nested separator
    /// still resets it) — only the emitted *entry* is suppressed.
    private static func walk(_ nodes: [MenuNode], path: [String], depth: Int, into entries: inout [SearchEntry]) {
        var section: String?

        for node in nodes {
            guard case .item(let item) = node else {
                if depth == 0 { entries.append(.separator) }
                section = nil
                continue
            }

            let hasText = !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let effectivePath = section.map { path + [$0] } ?? path
            let childPath = hasText ? effectivePath + [item.text] : effectivePath

            // `dropdown=false` (menu-bar-only): invisible to the panel — not
            // even as a section boundary — but still descends, exactly like
            // `flatten` treats it today.
            if item.params.dropdown == false {
                if !item.submenu.isEmpty { walk(item.submenu, path: childPath, depth: depth + 1, into: &entries) }
                continue
            }

            if item.params.swiftbar.header == true {
                // Mirrors MenuBuilder.makeItem's early return for
                // `header=true` (returns `NSMenuItem.sectionHeader(title:)`
                // before any submenu is ever built) — a header's submenu is
                // never part of the native dropdown, so it's never walked
                // here either.
                if hasText, depth == 0 { entries.append(.header(item.text)) }
                section = hasText ? item.text : nil   // opens (or, if titleless, just closes) scope for what follows
                continue
            }

            if hasText { entries.append(entry(for: item, path: effectivePath)) }
            // Always descend; empty text contributes no breadcrumb segment.
            if !item.submenu.isEmpty { walk(item.submenu, path: childPath, depth: depth + 1, into: &entries) }

            // `alternate=true`: `MenuBuilder.fill` adds this as a sibling
            // `NSMenuItem` right after `item` in the same menu (shown in place
            // of `item` while ⌥ is held), not a submenu child — flatten it the
            // same way, as a peer at `item`'s own level right after its
            // subtree, instead of the silent gap today where an alternate is
            // never shown, searched, or activatable at all.
            if let alt = item.alternate {
                let hasAltText = !alt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasAltText { entries.append(entry(for: alt, path: effectivePath)) }
                if !alt.submenu.isEmpty {
                    let altChildPath = hasAltText ? effectivePath + [alt.text] : effectivePath
                    walk(alt.submenu, path: altChildPath, depth: depth + 1, into: &entries)
                }
            }
        }
    }

    /// `.action` iff `item` is enabled, actionable, AND has no submenu of its
    /// own. `MenuBuilder.makeItem` (Sources/VeeMenu/MenuBuilder.swift) wires
    /// EITHER a submenu OR an action, never both — an item with both children
    /// and e.g. `shell=` is inert-on-click natively (its submenu opens
    /// instead), so a destructive action that never fires from the menu bar
    /// must not fire from the panel either (D2); the item still surfaces
    /// (searchable, non-activating) and its children still descend. Shared by
    /// an item's own row and its `alternate=true` sibling, which `makeItem`
    /// wires up exactly the same way.
    private static func entry(for item: MenuItem, path: [String]) -> SearchEntry {
        let disabled = item.params.disabled ?? false
        let hasSubmenu = !item.submenu.isEmpty
        let row = makeRow(item, path: path)
        return !disabled && !hasSubmenu && isActionable(item) ? .action(row) : .info(row)
    }

    private static func makeRow(_ item: MenuItem, path: [String]) -> FlatRow {
        let title = SearchText.fold(item.text)
        let haystack = SearchText.fold(([item.text] + path).joined(separator: " "))
        return FlatRow(item: item, path: path, title: title, haystack: haystack)
    }

    /// Cleans up a flattened entry list so structural furniture never appears
    /// without content around it: collapses runs of `.separator` to one, trims
    /// leading/trailing separators, and drops a `.header` with nothing under it
    /// (immediately followed by another header, a separator, or the end of the
    /// list). Iterates to a fixpoint — dropping a dangling header can expose a
    /// newly-trailing separator (and vice versa) — lists here are menu-sized,
    /// so this is cheap. Public so the cross-plugin aggregator, which
    /// concatenates several already-normalized lists with a separator spliced
    /// between each, can re-run it on the merged result.
    public static func normalized(_ entries: [SearchEntry]) -> [SearchEntry] {
        var result = entries
        var previous: [SearchEntry] = []
        while result != previous {
            previous = result
            result = collapseSeparators(result)
            result = dropDanglingHeaders(result)
        }
        return result
    }

    private static func collapseSeparators(_ entries: [SearchEntry]) -> [SearchEntry] {
        var result: [SearchEntry] = []
        for entry in entries {
            if case .separator = entry, case .separator = result.last { continue }
            result.append(entry)
        }
        if case .separator = result.first { result.removeFirst() }
        if case .separator = result.last { result.removeLast() }
        return result
    }

    private static func dropDanglingHeaders(_ entries: [SearchEntry]) -> [SearchEntry] {
        var result: [SearchEntry] = []
        for (index, entry) in entries.enumerated() {
            if case .header = entry {
                let next = index + 1 < entries.count ? entries[index + 1] : nil
                switch next {
                case nil, .header, .separator: continue   // dangling/empty section
                default: break
                }
            }
            result.append(entry)
        }
        return result
    }
}
