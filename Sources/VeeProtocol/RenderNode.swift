import Foundation

/// One node in the declarative render tree a plugin emits.
///
/// The wire format is intentionally minimal and React-agnostic: a `tag`
/// (component kind), a heterogeneous `props` bag, optional stable `key` for
/// keyed reconciliation, and ordered `children`. React (in the `plugins/`
/// authoring layer) compiles down to exactly this; so does a plugin written by
/// hand. The host never sees React — only this tree and JSON-Patch diffs of it.
///
/// The whole node is itself representable as a `JSONValue` (see `jsonValue`)
/// so that JSON Patch can diff/apply over a uniform value type.
public struct RenderNode: Codable, Hashable, Sendable {
    /// Component kind. Known core tags are in `Tag`, but the field is a free
    /// `String` so the wire format never has to change to add components.
    public var tag: String

    /// Stable identity for keyed children (maps to React `key`). Optional.
    public var key: String?

    /// Heterogeneous properties: title, subtitle, icon, actionId, placeholder…
    public var props: [String: JSONValue]

    /// Ordered children.
    public var children: [RenderNode]

    public init(tag: String,
                key: String? = nil,
                props: [String: JSONValue] = [:],
                children: [RenderNode] = []) {
        self.tag = tag
        self.key = key
        self.props = props
        self.children = children
    }

    /// The canonical set of core component tags. Plugins may emit others; the
    /// host renders unknown tags as an inert container (forward-compatible).
    public enum Tag {
        public static let root      = "root"
        public static let list      = "list"
        public static let listItem  = "list-item"
        public static let detail    = "detail"
        public static let form      = "form"
        public static let field     = "field"
        public static let action    = "action"
        public static let actionPanel = "action-panel"
        public static let text      = "text"
        public static let empty     = "empty-view"
    }
}

public extension RenderNode {
    /// Lossless projection into `JSONValue` so JSON Patch operates on one type.
    /// Shape: `{ "tag": ..., "key": ...?, "props": {...}, "children": [...] }`.
    /// `key` is omitted when nil so absent/null never produce spurious diffs.
    var jsonValue: JSONValue {
        var obj: [String: JSONValue] = [
            "tag": .string(tag),
            "props": .object(props),
            "children": .array(children.map(\.jsonValue)),
        ]
        if let key { obj["key"] = .string(key) }
        return .object(obj)
    }

    /// Reconstruct a `RenderNode` from its `jsonValue` projection.
    /// Throws `RenderNodeError` on malformed input.
    init(jsonValue: JSONValue) throws {
        guard case .object(let o) = jsonValue,
              let tag = o["tag"]?.stringValue else {
            throw RenderNodeError.malformed("expected object with string `tag`")
        }
        let props: [String: JSONValue]
        if let p = o["props"] {
            guard case .object(let po) = p else {
                throw RenderNodeError.malformed("`props` must be an object")
            }
            props = po
        } else {
            props = [:]
        }
        var children: [RenderNode] = []
        if let c = o["children"] {
            guard case .array(let ca) = c else {
                throw RenderNodeError.malformed("`children` must be an array")
            }
            children = try ca.map(RenderNode.init(jsonValue:))
        }
        self.init(tag: tag, key: o["key"]?.stringValue, props: props, children: children)
    }
}

public enum RenderNodeError: Error, Equatable, Sendable {
    case malformed(String)
}
