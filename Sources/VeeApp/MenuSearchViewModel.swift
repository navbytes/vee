import Foundation
import VeePluginFormat
import VeeSearch

/// The state behind Vee's menu surface: the entry set for one plugin, the live
/// query, the ranked results, and the keyboard selection. Kept free of
/// AppKit/SwiftUI so the filter + selection behavior is unit-tested directly.
///
/// **Entries are frozen for the transient panel.** It is on screen for seconds
/// while the user types and moves a selection through the list; re-ranking it
/// underneath them would reorder rows under the cursor. The panel reopens
/// against fresh entries next time, and never calls `update(entries:)`.
///
/// A detached window is the opposite case — it exists precisely to keep showing
/// current values — so it calls `update(entries:)` on every refresh. That is the
/// only difference between the two presentations' use of this model.
@MainActor
final class MenuSearchViewModel: ObservableObject {
    /// Every panel-visible entry for the plugin, in original order (the idle
    /// list) — action/info rows, section headers, and separators alike.
    /// Immutable for the transient panel; replaced wholesale on each refresh
    /// for a detached window (`update(entries:)`).
    private(set) var allEntries: [SearchEntry]

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

    /// Replaces the entry set with a plugin's freshly parsed menu — the detached
    /// window's liveness path. The transient panel never calls this; see the
    /// type's documentation for why.
    ///
    /// The live query survives, so a window filtered to `cpu` stays filtered to
    /// `cpu` across refreshes.
    ///
    /// The selection is carried by *position*, clamped forward to the nearest
    /// still-valid row. A live window re-ranks on the plugin's own cadence, so
    /// resetting to the top would snap the highlight back once a second on a
    /// 1-second plugin and make keyboard navigation unusable. Position is the
    /// right key here and text is not: a row worth watching is precisely one
    /// whose text keeps changing (`CPU 12%` -> `CPU 15%`). With the idle query
    /// `results` is `allEntries` in order, so this is structural position and
    /// holds still for any plugin emitting a stable row set.
    ///
    /// Getting it wrong is cosmetic by construction: the selection only draws a
    /// highlight, and activation reads `results[selection]` at the moment the
    /// user presses Return — always the row actually under the highlight, never
    /// a command captured earlier.
    func update(entries: [SearchEntry]) {
        let previous = selection
        allEntries = entries
        results = MenuSearch.search(query, in: entries)
        selection = Self.actionIndex(atOrAfter: previous, in: results)
            ?? Self.firstActionIndex(in: results)
    }

    /// `index` itself when it still addresses an `.action`, otherwise the
    /// nearest one after it; `nil` when the list has none left at or after it.
    private static func actionIndex(atOrAfter index: Int, in results: [SearchEntry]) -> Int? {
        guard index >= 0 else { return nil }
        if results.indices.contains(index), case .action = results[index] { return index }
        return actionIndex(after: index - 1, in: results)
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
