import Foundation
import VeePluginFormat

/// The key identifying one branch for expansion purposes: its ancestor titles,
/// outermost first, ending with the row's own text.
///
/// Menu nodes are value types with no identity, so this is the only handle a
/// refresh can be matched against. It is imperfect by construction — a plugin
/// that retitles a group each tick (`Disks (3)` → `Disks (4)`) changes its own
/// key — and `MenuTreeDisplay` is careful that the cost of a miss is that one
/// branch closing, never a cascade.
public typealias MenuPath = [String]

/// Narrows a resolved menu to what matches a query, **keeping its shape**.
///
/// This is the tree counterpart of the flat ranked search: the same matching,
/// projected onto structure instead of a list. Two consequences follow from
/// that and are deliberate:
///
/// - **Nothing is reordered.** A tree cannot rank — reordering rows would move
///   them out from under their parents — so results keep the order the plugin
///   authored. The flat projection (`MenuSearch`, still used by `vee search`)
///   is where ranking lives.
/// - **A matching row keeps its whole subtree.** Typing a group's name is how a
///   user asks for what is inside it, so the group's children come along
///   unfiltered rather than being narrowed again by a query that was about the
///   group, not them.
public enum MenuTreeFilter {
    /// Returns the subset of `nodes` matching `query`, preserving nesting and
    /// order. An empty or whitespace-only query is the idle state: `nodes`
    /// unchanged, structural furniture included.
    ///
    /// Once a query is typed, headers and separators are dropped: they are
    /// furniture that marks boundaries between rows which filtering has just
    /// pulled apart, so keeping them would draw dividers around groups that no
    /// longer exist.
    public static func filter(_ nodes: [MenuTreeNode], query: String) -> [MenuTreeNode] {
        let tokens = SearchText.tokens(SearchText.fold(query))
        guard !tokens.isEmpty else { return nodes }
        return prune(nodes, tokens: tokens)
    }

    private static func prune(_ nodes: [MenuTreeNode], tokens: [String]) -> [MenuTreeNode] {
        var kept: [MenuTreeNode] = []
        for node in nodes {
            guard case .row(let row) = node, !row.isHeader else { continue }
            if matches(row, tokens: tokens) {
                // A hit keeps everything under it — see the type's docs.
                kept.append(.row(row))
                continue
            }
            let children = prune(row.children, tokens: tokens)
            if !children.isEmpty {
                var narrowed = row
                narrowed.children = children
                kept.append(.row(narrowed))
            }
        }
        return kept
    }

    /// Every token must fuzzy-match the row's own text (multi-token AND) — the
    /// same semantics the flat search applies, minus the breadcrumb fallback,
    /// which a tree does not need: an ancestor match is expressed by keeping
    /// that ancestor's subtree rather than by scoring its descendants.
    static func matches(_ row: MenuRowSpec, tokens: [String]) -> Bool {
        let text = SearchText.fold(row.item.text)
        return tokens.allSatisfy { FuzzyScorer.score(query: $0, in: text) != nil }
    }
}
