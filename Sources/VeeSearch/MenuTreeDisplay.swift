import Foundation
import VeePluginFormat

/// One line a tree surface actually draws, with everything the view needs to
/// place it: how deep to indent, whether it can open, and the key its open
/// state is remembered under.
public enum VisibleNode: Equatable, Sendable {
    case row(VisibleRow)
    case header(String, depth: Int)
    case separator(depth: Int)

    /// Whether the keyboard highlight can land here. Headers and separators are
    /// furniture; every other line is reachable — including a parent, so it can
    /// be opened and closed from the keyboard.
    public var isSelectable: Bool {
        if case .row = self { return true }
        return false
    }

    public var row: VisibleRow? {
        if case .row(let row) = self { return row }
        return nil
    }
}

/// A drawable row: the resolved row plus its place in the structure.
public struct VisibleRow: Equatable, Sendable {
    public let spec: MenuRowSpec
    /// Nesting level; 0 is the top of the menu.
    public let depth: Int
    /// The key this row's open state is remembered under (`MenuPath`).
    public let key: MenuPath
    /// Whether this row has children to show. A row can declare a submenu whose
    /// children are all hidden, and that row has nothing to open.
    public let canExpand: Bool
    /// Whether its children are currently shown.
    public let isExpanded: Bool

    public init(spec: MenuRowSpec, depth: Int, key: MenuPath, canExpand: Bool, isExpanded: Bool) {
        self.spec = spec
        self.depth = depth
        self.key = key
        self.canExpand = canExpand
        self.isExpanded = isExpanded
    }
}

/// Flattens a resolved menu into the lines currently on screen, honouring which
/// branches are open.
///
/// The tree is what the surface *is*; this is the list it draws. Keeping the
/// projection separate means keyboard navigation stays a simple index into a
/// list — the same shape it had when the surface was genuinely flat — while the
/// content it walks is a real hierarchy.
public enum MenuTreeDisplay {
    /// The lines to draw for `nodes`.
    ///
    /// `expanded` holds the keys of open branches. `revealAll` overrides it and
    /// opens everything, which is what a filtered tree does: a query has already
    /// narrowed the menu to matches, so hiding them behind closed parents would
    /// make the user open their way to results they explicitly asked for.
    ///
    /// `alternatesActive` is the live ⌥ state. Idle, an `alternate=` pair
    /// resolves to **one** line — the primary, or the alternate while ⌥ is
    /// held — swapped in place so the list's length and indices never change
    /// and an index-based selection rides through the swap. The filtered
    /// projection (`revealAll`) ignores the flag and emits both halves as
    /// ordinary rows: a query is explicit intent, and hiding an exact match
    /// behind a modifier would be hostile — the same call `vee search` makes.
    public static func visibleNodes(
        _ nodes: [MenuTreeNode],
        expanded: Set<MenuPath>,
        revealAll: Bool = false,
        alternatesActive: Bool = false
    ) -> [VisibleNode] {
        var result: [VisibleNode] = []
        walk(
            nodes, path: [], depth: 0, expanded: expanded,
            revealAll: revealAll, alternatesActive: alternatesActive, into: &result
        )
        return result
    }

    /// Every branch key present in `nodes` — what a refresh's surviving open
    /// branches are intersected against, so a branch that vanished takes only
    /// itself with it.
    public static func allKeys(_ nodes: [MenuTreeNode]) -> Set<MenuPath> {
        var keys: Set<MenuPath> = []
        collectKeys(nodes, path: [], into: &keys)
        return keys
    }

    private static func walk(
        _ nodes: [MenuTreeNode],
        path: MenuPath,
        depth: Int,
        expanded: Set<MenuPath>,
        revealAll: Bool,
        alternatesActive: Bool,
        into result: inout [VisibleNode]
    ) {
        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            index += 1
            switch node {
            case .separator:
                result.append(.separator(depth: depth))
            case .row(let spec):
                if spec.isHeader {
                    result.append(.header(spec.item.text, depth: depth))
                    continue
                }
                // A pair is a primary immediately followed by its alternate —
                // the adjacency `MenuTree.build` guarantees. Idle, the pair
                // draws as one line; which half is `alternatesActive`'s call.
                // An alternate with no primary neighbor (a hand-built tree, or
                // one whose primary a filter pruned) renders as an ordinary
                // row in both states rather than vanishing — the same fallback
                // AppKit applies to an unpaired `isAlternate` item.
                var chosen = spec
                if !revealAll, !spec.isAlternate, index < nodes.count,
                   case .row(let alternate) = nodes[index], alternate.isAlternate, !alternate.isHeader {
                    if alternatesActive { chosen = alternate }
                    index += 1
                }
                let key = path + [chosen.item.text]
                let canExpand = !chosen.children.isEmpty
                let isExpanded = canExpand && (revealAll || expanded.contains(key))
                result.append(.row(VisibleRow(
                    spec: chosen, depth: depth, key: key, canExpand: canExpand, isExpanded: isExpanded
                )))
                if isExpanded {
                    walk(
                        chosen.children, path: key, depth: depth + 1, expanded: expanded,
                        revealAll: revealAll, alternatesActive: alternatesActive, into: &result
                    )
                }
            }
        }
    }

    private static func collectKeys(_ nodes: [MenuTreeNode], path: MenuPath, into keys: inout Set<MenuPath>) {
        for node in nodes {
            guard case .row(let spec) = node, !spec.isHeader else { continue }
            let key = path + [spec.item.text]
            if !spec.children.isEmpty {
                keys.insert(key)
                collectKeys(spec.children, path: key, into: &keys)
            }
        }
    }
}
