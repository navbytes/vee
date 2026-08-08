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
        walk(nodes, path: [], into: &entries)
        return normalized(entries)
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

    /// Depth-first walk (emission order matches descent order). A `header=true`
    /// item doesn't just emit its own title — it opens a *section* that
    /// "adopts" the following siblings at this level, as if the header were an
    /// extra ancestor group: their row path (breadcrumb + haystack) and any
    /// further descent both fold in the section title, so typing the section
    /// name surfaces its rows. The section resets at the next header or
    /// separator at the same level. `section` is a local to this call frame,
    /// so nested submenus always start their own tracking fresh.
    private static func walk(_ nodes: [MenuNode], path: [String], into entries: inout [SearchEntry]) {
        var section: String?

        for node in nodes {
            guard case .item(let item) = node else {
                entries.append(.separator)
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
                if !item.submenu.isEmpty { walk(item.submenu, path: childPath, into: &entries) }
                continue
            }

            if item.params.swiftbar.header == true {
                if hasText { entries.append(.header(item.text)) }
                if !item.submenu.isEmpty { walk(item.submenu, path: childPath, into: &entries) }
                section = hasText ? item.text : nil   // opens (or, if titleless, just closes) scope for what follows
                continue
            }

            if hasText {
                let disabled = item.params.disabled ?? false
                let row = makeRow(item, path: effectivePath)
                entries.append(!disabled && isActionable(item) ? .action(row) : .info(row))
            }
            // Always descend; empty text contributes no breadcrumb segment.
            if !item.submenu.isEmpty { walk(item.submenu, path: childPath, into: &entries) }
        }
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
