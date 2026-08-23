import Foundation
import VeePluginFormat
import VeeSearch

/// The state behind Vee's menu surface: one plugin's resolved menu, which of its
/// branches are open, the live query, and the keyboard selection. Kept free of
/// AppKit/SwiftUI so the filter, expansion, and selection behavior is unit-tested
/// directly.
///
/// **The tree is frozen for the transient panel.** It is on screen for seconds
/// while the user types and moves a selection through it; replacing it
/// underneath them would move rows under the cursor. The panel reopens against
/// a fresh tree next time, and never calls `update(nodes:)`.
///
/// A detached window is the opposite case — it exists precisely to keep showing
/// current values — so it calls `update(nodes:)` on every refresh. That is the
/// only difference between the two presentations' use of this model.
@MainActor
final class MenuSearchViewModel: ObservableObject {
    /// The plugin's whole resolved menu, in authored order. Immutable for the
    /// transient panel; replaced wholesale on each refresh for a window.
    private(set) var allNodes: [MenuTreeNode]

    /// The live filter text. Editing it re-narrows the tree and moves the
    /// selection to the first result.
    @Published var query: String = "" {
        didSet { recompute(resetSelection: true) }
    }

    /// The lines currently drawn, in order.
    @Published private(set) var visible: [VisibleNode] = []

    /// Index into `visible` of the keyboard-highlighted line. Headers and
    /// separators are not selectable, so this always sits on a row — `-1` when
    /// there are none.
    @Published var selection: Int = -1

    /// The open branches, keyed by title path. Survives a refresh; see
    /// `update(nodes:)`.
    private var expanded: Set<MenuPath> = []

    /// The narrowed tree for the current query — `allNodes` when idle.
    private var filtered: [MenuTreeNode] = []

    /// Whether a query is active, in which case every surviving branch is shown
    /// open regardless of `expanded`.
    private var isFiltering: Bool { !SearchText.isBlank(query) }

    init(nodes: [MenuTreeNode]) {
        self.allNodes = nodes
        recompute(resetSelection: true)
    }

    private func recompute(resetSelection: Bool) {
        filtered = MenuTreeFilter.filter(allNodes, query: query)
        visible = MenuTreeDisplay.visibleNodes(filtered, expanded: expanded, revealAll: isFiltering)
        if resetSelection {
            selection = Self.firstSelectable(in: visible)
        }
    }

    /// Replaces the menu with a plugin's freshly parsed one — the detached
    /// window's liveness path. The transient panel never calls this.
    ///
    /// The live query survives, so a window filtered to `cpu` stays filtered.
    ///
    /// **Open branches survive too**, which is the whole point of a window you
    /// leave up: a plugin refreshing once a second would otherwise close
    /// everything the user opened, once a second. Branches are matched by title
    /// path, and the surviving set is intersected with the keys the new tree
    /// actually has — so a branch that vanished (or was retitled, which reads as
    /// the same thing) drops out **alone**, and every other open branch is
    /// untouched. That containment is the design's answer to title-keying being
    /// imperfect: the cost of a miss is one branch closing, never a cascade.
    ///
    /// The selection is carried by *position*, clamped forward to the nearest
    /// still-valid row. A live window re-derives on the plugin's own cadence, so
    /// resetting to the top would snap the highlight back once a second and make
    /// keyboard navigation unusable. Position is the right key here and text is
    /// not: a row worth watching is precisely one whose text keeps changing
    /// (`CPU 12%` → `CPU 15%`).
    ///
    /// Getting it wrong is cosmetic by construction: the selection only draws a
    /// highlight, and activation reads `visible[selection]` at the moment the
    /// user presses Return — always the row actually under the highlight, never
    /// a command captured earlier.
    func update(nodes: [MenuTreeNode]) {
        let previous = selection
        allNodes = nodes
        expanded.formIntersection(MenuTreeDisplay.allKeys(nodes))
        recompute(resetSelection: false)
        selection = Self.selectable(atOrAfter: previous, in: visible) ?? Self.firstSelectable(in: visible)
    }

    // MARK: - Expansion

    func isExpanded(_ key: MenuPath) -> Bool { expanded.contains(key) }

    /// Opens or closes one branch. A no-op while filtering, where everything is
    /// shown open regardless.
    func toggle(_ key: MenuPath) {
        guard !isFiltering else { return }
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        recompute(resetSelection: false)
        selection = Self.selectable(atOrAfter: selection, in: visible) ?? Self.firstSelectable(in: visible)
    }

    /// Opens the selected branch, or moves into it when it is already open.
    /// The `→` half of menu-style keyboard navigation.
    func expandSelection() {
        guard let row = selectedVisibleRow(), row.canExpand else { return }
        if row.isExpanded { moveDown() } else { toggle(row.key) }
    }

    /// Closes the selected branch, or moves to its parent when it is a leaf.
    /// The `←` half.
    func collapseSelection() {
        guard let row = selectedVisibleRow() else { return }
        if row.canExpand, row.isExpanded { toggle(row.key); return }
        guard row.depth > 0 else { return }
        // Walk back to the nearest shallower row — this row's parent.
        var i = selection - 1
        while i >= 0 {
            if let candidate = visible[i].row, candidate.depth < row.depth { selection = i; return }
            i -= 1
        }
    }

    // MARK: - Selection

    /// The highlighted row's spec, or `nil` when nothing is highlighted.
    func selectedRow() -> MenuRowSpec? { selectedVisibleRow()?.spec }

    func selectedVisibleRow() -> VisibleRow? {
        guard visible.indices.contains(selection) else { return nil }
        return visible[selection].row
    }

    /// Moves the highlight down one selectable line, clamped (no wrap).
    func moveDown() {
        guard let next = Self.selectable(after: selection, in: visible) else { return }
        selection = next
    }

    /// Moves the highlight up one selectable line, clamped (no wrap).
    func moveUp() {
        guard let previous = Self.selectable(before: selection, in: visible) else { return }
        selection = previous
    }

    private static func firstSelectable(in nodes: [VisibleNode]) -> Int {
        nodes.firstIndex(where: \.isSelectable) ?? -1
    }

    /// `index` itself when it still addresses a row, otherwise the nearest one
    /// after it; `nil` when the list has none left at or after it.
    private static func selectable(atOrAfter index: Int, in nodes: [VisibleNode]) -> Int? {
        guard index >= 0 else { return nil }
        if nodes.indices.contains(index), nodes[index].isSelectable { return index }
        return selectable(after: index - 1, in: nodes)
    }

    private static func selectable(after index: Int, in nodes: [VisibleNode]) -> Int? {
        var i = index + 1
        while i < nodes.count {
            if nodes[i].isSelectable { return i }
            i += 1
        }
        return nil
    }

    private static func selectable(before index: Int, in nodes: [VisibleNode]) -> Int? {
        var i = index - 1
        while i >= 0 {
            if nodes[i].isSelectable { return i }
            i -= 1
        }
        return nil
    }
}
