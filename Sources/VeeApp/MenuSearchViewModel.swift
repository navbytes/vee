import Foundation
import VeePluginFormat
import VeeSearch

/// The state behind the search panel: the frozen entry set for one plugin, the
/// live query, the ranked results, and the keyboard selection. Kept free of
/// AppKit/SwiftUI so the filter + selection behavior is unit-tested directly.
///
/// Entries are frozen at open (the plugin may re-run on its interval while the
/// panel is up); the panel reopens against fresh entries next time.
@MainActor
final class MenuSearchViewModel: ObservableObject {
    /// Every panel-visible entry for the plugin, in original order (the idle
    /// list) — action/info rows, section headers, and separators alike.
    let allEntries: [SearchEntry]

    /// The live search text. Editing it re-filters and resets the selection to
    /// the top (best) result.
    @Published var query: String = "" {
        didSet { recompute() }
    }

    /// The ranked entries for the current query (all entries when the query is
    /// empty).
    @Published private(set) var results: [SearchEntry]

    /// Index into `results` of the keyboard-highlighted row. Headers,
    /// separators, and `.info` rows aren't selectable, so this always sits on
    /// an `.action` index — `-1` when `results` has none.
    @Published var selection: Int = -1

    init(entries: [SearchEntry]) {
        self.allEntries = entries
        let results = MenuSearch.search("", in: entries)
        self.results = results
        self.selection = Self.firstActionIndex(in: results)
    }

    private func recompute() {
        results = MenuSearch.search(query, in: allEntries)
        selection = Self.firstActionIndex(in: results)   // highlight the best match on every keystroke
    }

    /// The currently highlighted row, or `nil` when there is no `.action`
    /// entry at `selection` (including the empty-selection `-1` case).
    func selectedRow() -> FlatRow? {
        guard results.indices.contains(selection), case .action(let row) = results[selection] else { return nil }
        return row
    }

    /// Moves the highlight to the next `.action` entry below, clamped (no
    /// wrap) at the last one.
    func moveDown() {
        guard let next = Self.actionIndex(after: selection, in: results) else { return }
        selection = next
    }

    /// Moves the highlight to the next `.action` entry above, clamped (no
    /// wrap) at the first one.
    func moveUp() {
        guard let previous = Self.actionIndex(before: selection, in: results) else { return }
        selection = previous
    }

    private static func firstActionIndex(in results: [SearchEntry]) -> Int {
        results.firstIndex {
            if case .action = $0 { return true }
            return false
        } ?? -1
    }

    private static func actionIndex(after index: Int, in results: [SearchEntry]) -> Int? {
        var i = index + 1
        while i < results.count {
            if case .action = results[i] { return i }
            i += 1
        }
        return nil
    }

    private static func actionIndex(before index: Int, in results: [SearchEntry]) -> Int? {
        var i = index - 1
        while i >= 0 {
            if case .action = results[i] { return i }
            i -= 1
        }
        return nil
    }
}
