// The FluidKit view vocabulary. Each view maps one-to-one onto a `ViewNode`;
// the names and modifiers follow SwiftUI wherever the meaning is the same.

public struct Text: FluidView {
    var string: String
    var textStyle: TextStyle = .body
    var textRole: Role = .primary

    public init(_ string: String) { self.string = string }

    public func style(_ style: TextStyle) -> Text { var copy = self; copy.textStyle = style; return copy }
    public func role(_ role: Role) -> Text { var copy = self; copy.textRole = role; return copy }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.text(string, style: textStyle, role: textRole)]
    }
}

/// A title with an SF Symbol — the usual menu-bar content.
public struct Label: FluidView {
    var title: String
    var symbol: String
    var labelRole: Role = .primary

    public init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    public func role(_ role: Role) -> Label { var copy = self; copy.labelRole = role; return copy }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.label(title, symbol: symbol, role: labelRole)]
    }
}

public struct VStack: FluidView {
    var spacing: Double?
    var content: ViewContent

    public init(spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.stack(axis: .vertical, spacing: spacing, children: content.resolve(in: context))]
    }
}

public struct HStack: FluidView {
    var spacing: Double?
    var content: ViewContent

    public init(spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.stack(axis: .horizontal, spacing: spacing, children: content.resolve(in: context))]
    }
}

public struct List: FluidView {
    var searchable: Bool
    var content: ViewContent

    public init(searchable: Bool = false, @ViewBuilder content: () -> ViewContent) {
        self.searchable = searchable
        self.content = content()
    }

    /// One row per element: `List(prs, searchable: true) { pr in Row(pr.title) }`.
    public init<Data: Sequence>(_ data: Data, searchable: Bool = false, @ViewBuilder row: (Data.Element) -> ViewContent) {
        self.searchable = searchable
        self.content = data.flatMap(row)
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.list(searchable: searchable, children: content.resolve(in: context))]
    }
}

public struct Section: FluidView {
    var title: String?
    var content: ViewContent

    public init(_ title: String? = nil, @ViewBuilder content: () -> ViewContent) {
        self.title = title
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.section(title: title, children: content.resolve(in: context))]
    }
}

/// Repeats content for each element, inside a stack or section.
public struct ForEach: FluidView {
    var content: ViewContent

    public init<Data: Sequence>(_ data: Data, @ViewBuilder content: (Data.Element) -> ViewContent) {
        self.content = data.flatMap(content)
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        content.resolve(in: context)
    }
}

/// A list entry with trailing accessories and actions.
public struct Row: FluidView {
    var key: String
    var title: String
    var subtitle: String?
    var symbol: String?
    var accessories: [ViewNode] = []
    var actions: [(title: String, shortcut: String?, role: Role, handler: RenderContext.Handler)] = []

    /// `key` defaults to the title; give one explicitly when titles can repeat
    /// or change (an id from your data is ideal).
    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, key: String? = nil) {
        self.key = key ?? title
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    public func badge(_ text: String, role: Role = .secondary) -> Row {
        var copy = self
        copy.accessories.append(.badge(text, role: role))
        return copy
    }

    public func progress(_ value: Double, total: Double = 1, role: Role = .accent) -> Row {
        var copy = self
        copy.accessories.append(.progress(value: value, total: total, label: nil, role: role))
        return copy
    }

    /// Adds an action. The first one is what a click on the row does.
    public func action(_ title: String, shortcut: String? = nil, role: Role = .primary, perform: @escaping @MainActor () async throws -> Void) -> Row {
        var copy = self
        copy.actions.append((title, shortcut, role, { _ in try await perform() }))
        return copy
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let refs = actions.map { action in
            ActionRef(id: context.register("row/\(key)/\(action.title)", action.handler), title: action.title, shortcut: action.shortcut, role: action.role)
        }
        return [.row(RowNode(key: key, title: title, subtitle: subtitle, symbol: symbol, accessories: accessories, actions: refs))]
    }
}

public struct Badge: FluidView {
    var text: String
    var role: Role

    public init(_ text: String, role: Role = .secondary) {
        self.text = text
        self.role = role
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.badge(text, role: role)] }
}

public struct Button: FluidView {
    var title: String
    var symbol: String?
    var role: Role
    var key: String?
    var handler: RenderContext.Handler

    public init(_ title: String, symbol: String? = nil, role: Role = .primary, key: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.key = key
        self.handler = { _ in try await action() }
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let id = context.register("button/\(key ?? title)", handler)
        return [.button(title: title, symbol: symbol, role: role, action: id)]
    }
}

public struct Toggle: FluidView {
    var title: String
    var isOn: Bool
    var key: String?
    var onChange: @MainActor (Bool) async throws -> Void

    /// The host sends the new state; update your own property in `onChange`
    /// and the next render shows it.
    public init(_ title: String, isOn: Bool, key: String? = nil, onChange: @escaping @MainActor (Bool) async throws -> Void) {
        self.title = title
        self.isOn = isOn
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let current = isOn
        let change = onChange
        let id = context.register("toggle/\(key ?? title)") { value in
            if case .bool(let newValue) = value {
                try await change(newValue)
            } else {
                try await change(!current)
            }
        }
        return [.toggle(title: title, isOn: isOn, action: id)]
    }
}

public struct ProgressBar: FluidView {
    var value: Double
    var total: Double
    var label: String?
    var role: Role

    public init(_ label: String? = nil, value: Double, total: Double = 1, role: Role = .accent) {
        self.label = label
        self.value = value
        self.total = total
        self.role = role
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.progress(value: value, total: total, label: label, role: role)]
    }
}

public struct Divider: FluidView {
    public init() {}
    public func resolve(in context: RenderContext) -> [ViewNode] { [.divider] }
}
