import Foundation
import VeeProtocol

/// View-model layer derived from the plugin's `RenderNode` tree.
///
/// This is the architecture's "view-model shielding" boundary (docs/ARCHITECTURE.md
/// §3): the AppKit seams (`LauncherWindowPresenting`, `MenuBarPresenting`) only
/// ever see these value types, never the raw render tree or JSON-Patch. So a
/// change to the wire representation reshapes the projection here and the native
/// views are unaffected.
///
/// Projection rules:
///   - A `list` node → `ListViewModel` (its `list-item` children → items).
///   - A `detail` node → `DetailViewModel`.
///   - An `empty-view` node → `EmptyViewModel`.
///   - Item identity is `node.key` when present, else `props["id"]` (string).
///   - Actions are gathered from an item's `action` / `action-panel` subtree.
///   - Unknown tags render as an inert container (forward-compatible): they
///     contribute nothing themselves but their children are still walked, so a
///     future wrapper tag never hides a list/detail nested inside it.

// MARK: - The root projection

/// What the launcher window should render right now. Exactly one case is the
/// "primary surface" the plugin emitted at the top of its tree.
public enum RootViewModel: Equatable, Sendable {
    case list(ListViewModel)
    case detail(DetailViewModel)
    case empty(EmptyViewModel)
    /// Cold-open / in-flight surface shown before the first candidates or render
    /// arrive (R2-MED-4): a "Loading…" title + subtle indicator over the empty
    /// pane. Cleared the moment real content lands.
    case loading(LoadingViewModel)
    /// A tree with no recognized primary surface (e.g. only unknown tags).
    case none
}

public struct ListViewModel: Equatable, Sendable {
    public var items: [ListItemViewModel]
    /// The currently selected item id, if any (owned by the coordinator's
    /// selection rule; projected in for the view).
    public var selectedID: String?
    /// Optional section header shown above the list (e.g. "Applications").
    public var sectionTitle: String?
    public init(items: [ListItemViewModel], selectedID: String? = nil, sectionTitle: String? = nil) {
        self.items = items
        self.selectedID = selectedID
        self.sectionTitle = sectionTitle
    }
}

public struct ListItemViewModel: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: String?
    /// Right-aligned secondary text (e.g. the result type, "Application").
    public var accessoryText: String?
    public var actions: [ActionViewModel]
    /// Character positions in `title` that matched the current query, for
    /// highlighting. Empty when there's no active query/match (→ plain title).
    /// Threaded in by the coordinator from `ScoredCandidate.matchedIndices`.
    public var matchedIndices: [Int]
    public init(id: String, title: String, subtitle: String? = nil,
                icon: String? = nil, accessoryText: String? = nil,
                actions: [ActionViewModel] = [], matchedIndices: [Int] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.icon = icon; self.accessoryText = accessoryText; self.actions = actions
        self.matchedIndices = matchedIndices
    }
}

/// One label/value pair in a detail pane's metadata rail (e.g. "Size" → "4.2 MB").
public struct DetailMetadataRow: Equatable, Sendable {
    public var label: String
    public var value: String
    public init(label: String, value: String) {
        self.label = label; self.value = value
    }
}

public struct DetailViewModel: Equatable, Sendable {
    public var title: String?
    public var markdown: String
    /// Optional icon hint shown in the detail header (SF Symbol / path / URL).
    public var icon: String?
    /// Label/value rows shown in the metadata rail above the body. Default [].
    public var metadata: [DetailMetadataRow]
    public init(title: String?, markdown: String,
                icon: String? = nil, metadata: [DetailMetadataRow] = []) {
        self.title = title; self.markdown = markdown
        self.icon = icon; self.metadata = metadata
    }
}

public struct ActionViewModel: Equatable, Identifiable, Sendable {
    /// Echoed back to the plugin via `host.invokeAction`.
    public var actionId: String
    public var title: String
    public var shortcut: String?
    public var id: String { actionId }
    public init(actionId: String, title: String, shortcut: String? = nil) {
        self.actionId = actionId; self.title = title; self.shortcut = shortcut
    }
}

public struct EmptyViewModel: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public init(title: String?, description: String?) {
        self.title = title; self.description = description
    }
}

/// Cold-open loading surface (R2-MED-4). Mirrors the empty-state shape (a title +
/// optional description) but the AppKit view also shows a subtle progress
/// indicator, so the launcher gives feedback while app discovery + the ~5000-app
/// enumeration are still in flight instead of presenting a blank list.
public struct LoadingViewModel: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public init(title: String? = "Loading…", description: String? = nil) {
        self.title = title; self.description = description
    }
}

/// A menubar entry projected from a menu-bar command's render tree.
public struct MenuBarItemViewModel: Equatable, Identifiable, Sendable {
    public var actionId: String
    public var title: String
    public var id: String { actionId }
    public init(actionId: String, title: String) {
        self.actionId = actionId; self.title = title
    }
}

// MARK: - Projection from RenderNode

/// Pure `RenderNode` → view-model projection. No state, no OS, no transport —
/// just the value-tree transform. Fully unit-testable.
public enum ViewModelProjector {

    /// Project a render tree (typically rooted at `root`) into the launcher's
    /// primary surface. Walks past `root` and inert/unknown wrappers to find the
    /// first recognized surface (list / detail / empty-view).
    public static func project(_ node: RenderNode) -> RootViewModel {
        // Depth-first search for the first recognized primary surface. `root`
        // and unknown tags are inert containers we descend through.
        if let surface = firstSurface(in: node) {
            return surface
        }
        return .none
    }

    private static func firstSurface(in node: RenderNode) -> RootViewModel? {
        switch node.tag {
        case RenderNode.Tag.list:
            return .list(listViewModel(from: node))
        case RenderNode.Tag.detail:
            return .detail(detailViewModel(from: node))
        case RenderNode.Tag.empty:
            return .empty(emptyViewModel(from: node))
        default:
            // `root` and any unknown tag: inert container — search children.
            for child in node.children {
                if let found = firstSurface(in: child) { return found }
            }
            return nil
        }
    }

    /// Project a `list` node into a `ListViewModel` (selection left nil; the
    /// coordinator fills it from its selection rule).
    public static func listViewModel(from node: RenderNode) -> ListViewModel {
        let items = node.children
            .filter { $0.tag == RenderNode.Tag.listItem }
            .map(listItemViewModel(from:))
        return ListViewModel(items: items, selectedID: nil)
    }

    public static func listItemViewModel(from node: RenderNode) -> ListItemViewModel {
        ListItemViewModel(
            id: identity(of: node),
            title: node.props["title"]?.stringValue ?? "",
            subtitle: node.props["subtitle"]?.stringValue,
            icon: node.props["icon"]?.stringValue,
            accessoryText: node.props["accessory"]?.stringValue,
            actions: actions(in: node))
    }

    public static func detailViewModel(from node: RenderNode) -> DetailViewModel {
        DetailViewModel(
            title: node.props["title"]?.stringValue,
            // Accept either `markdown` or `value` so a plain text detail still projects.
            markdown: node.props["markdown"]?.stringValue
                ?? node.props["value"]?.stringValue
                ?? "",
            icon: node.props["icon"]?.stringValue,
            metadata: metadataRows(from: node.props["metadata"]))
    }

    /// Parse a `metadata` prop into label/value rows. The wire shape is an array
    /// of objects `{label, value}`; both must be strings. Rows missing either
    /// field are skipped (forward-compatible). Anything but an array → no rows.
    public static func metadataRows(from value: JSONValue?) -> [DetailMetadataRow] {
        guard let entries = value?.arrayValue else { return [] }
        return entries.compactMap { entry in
            guard let label = entry["label"]?.stringValue,
                  let value = entry["value"]?.stringValue else { return nil }
            return DetailMetadataRow(label: label, value: value)
        }
    }

    public static func emptyViewModel(from node: RenderNode) -> EmptyViewModel {
        EmptyViewModel(
            title: node.props["title"]?.stringValue,
            description: node.props["description"]?.stringValue)
    }

    /// Identity of a list-item: the node `key`, else `props["id"]`, else "".
    public static func identity(of node: RenderNode) -> String {
        if let key = node.key { return key }
        if let id = node.props["id"]?.stringValue { return id }
        return ""
    }

    /// Gather actions from an item's subtree: direct `action` children and any
    /// inside an `action-panel`. Walks one level of containers so both
    /// `item → action` and `item → action-panel → action` shapes work.
    public static func actions(in node: RenderNode) -> [ActionViewModel] {
        var out: [ActionViewModel] = []
        collectActions(in: node, into: &out)
        return out
    }

    private static func collectActions(in node: RenderNode, into out: inout [ActionViewModel]) {
        for child in node.children {
            switch child.tag {
            case RenderNode.Tag.action:
                if let action = actionViewModel(from: child) { out.append(action) }
            case RenderNode.Tag.actionPanel:
                // Descend one panel level for nested actions.
                collectActions(in: child, into: &out)
            default:
                continue
            }
        }
    }

    public static func actionViewModel(from node: RenderNode) -> ActionViewModel? {
        // Accept `actionId` (canonical) or fall back to `id`.
        guard let actionId = node.props["actionId"]?.stringValue
            ?? node.props["id"]?.stringValue else { return nil }
        return ActionViewModel(
            actionId: actionId,
            title: node.props["title"]?.stringValue ?? "",
            shortcut: node.props["shortcut"]?.stringValue)
    }
}
