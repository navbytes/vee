import Foundation
import VeePluginFormat
import VeeSearch

/// The state behind the search panel: the frozen row set for one plugin, the
/// live query, the ranked results, and the keyboard selection. Kept free of
/// AppKit/SwiftUI so the filter + selection behavior is unit-tested directly.
///
/// Rows are frozen at open (the plugin may re-run on its interval while the
/// panel is up); the panel reopens against fresh rows next time.
@MainActor
final class MenuSearchViewModel: ObservableObject {
    /// Every activatable row for the plugin, in original order (the idle list).
    let allRows: [FlatRow]

    /// The live search text. Editing it re-filters and resets the selection to
    /// the top (best) result.
    @Published var query: String = "" {
        didSet { recompute() }
    }

    /// The ranked rows for the current query (all rows when the query is empty).
    @Published private(set) var results: [FlatRow]

    /// Index into `results` of the keyboard-highlighted row. Always valid when
    /// `results` is non-empty; `0` otherwise.
    @Published var selection: Int = 0

    init(rows: [FlatRow]) {
        self.allRows = rows
        self.results = MenuSearch.search("", in: rows)
    }

    private func recompute() {
        results = MenuSearch.search(query, in: allRows)
        selection = 0   // highlight the best match on every keystroke
    }

    /// The currently highlighted row, or `nil` when there are no results.
    func selectedRow() -> FlatRow? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// Moves the highlight down one row, clamped to the last result.
    func moveDown() {
        guard !results.isEmpty else { return }
        selection = min(selection + 1, results.count - 1)
    }

    /// Moves the highlight up one row, clamped to the first result.
    func moveUp() {
        guard !results.isEmpty else { return }
        selection = max(selection - 1, 0)
    }
}
