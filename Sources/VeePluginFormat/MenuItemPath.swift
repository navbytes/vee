import Foundation

/// The structural address of one item inside a dropdown tree: the index of the
/// node at each level, outermost first. `[2]` is the third top-level node; `[2, 0]`
/// is the first node of that item's submenu.
///
/// This exists so a surface that outlives one render — a detached window
/// watching a row — can re-find "the same row" in the *next* parse. Matching on
/// the row's text would be exactly wrong for that job: a row worth watching is
/// one whose text keeps changing (`CPU 12%` → `CPU 15%`). Its position in the
/// tree is the part that holds still, so that is what we key on.
///
/// The trade-off is the honest one: a plugin that reorders or conditionally
/// omits rows between refreshes will resolve to a different row, or to none.
/// Callers must treat `item(at:in:)` returning `nil` — or returning an item that
/// no longer carries the payload they wanted — as "this row is gone", not as an
/// error to paper over.
public typealias MenuItemPath = [Int]

public enum MenuItemLocator {
    /// Guards the walk against a pathological tree, matching the depth cap the
    /// JSON parser already applies to `submenu` nesting.
    static let maxDepth = 64

    /// The path of the first node whose item equals `item`, in depth-first
    /// order. `nil` when the item isn't in this tree.
    ///
    /// First-match is deliberate: two rows can be genuinely identical (same
    /// text, same params), and there is no way to tell them apart from the item
    /// alone. Watching the first is predictable; refusing to watch either is not
    /// what the user asked for.
    public static func path(of item: MenuItem, in nodes: [MenuNode]) -> MenuItemPath? {
        search(nodes, for: item, prefix: [], depth: 0)
    }

    private static func search(_ nodes: [MenuNode], for item: MenuItem, prefix: MenuItemPath, depth: Int) -> MenuItemPath? {
        guard depth < maxDepth else { return nil }
        for (index, node) in nodes.enumerated() {
            guard case .item(let candidate) = node else { continue }
            let here = prefix + [index]
            if candidate == item { return here }
            if let found = search(candidate.submenu, for: item, prefix: here, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// The item at `path`, or `nil` if the tree no longer has a node there (the
    /// plugin shrank, reordered, or replaced that row with a separator).
    public static func item(at path: MenuItemPath, in nodes: [MenuNode]) -> MenuItem? {
        guard !path.isEmpty, path.count <= maxDepth else { return nil }
        var level = nodes
        var found: MenuItem?
        for index in path {
            guard level.indices.contains(index), case .item(let candidate) = level[index] else { return nil }
            found = candidate
            level = candidate.submenu
        }
        return found
    }
}
