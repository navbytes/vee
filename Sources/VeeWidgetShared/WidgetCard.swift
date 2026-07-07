import Foundation

/// The layout a `WidgetCard` renders with. Each template is a native SwiftUI
/// view (see `WidgetExtension`) that adapts across the `small`/`medium`/`large`
/// widget families. An unrecognized value from a plugin's JSON is mapped to
/// `.stat` by `WidgetCardParser` (kept strict/failable here; the parser owns
/// the tolerant fallback + diagnostic since the raw string is otherwise lost).
public enum WidgetTemplate: String, Codable, Equatable, Sendable {
    case stat
    case gauge
    case trend
    case list
    case board
}

/// The health state a card reports, driving both styling and the health
/// roll-up widget (mirrors `PluginSnapshot.isError`, but plugin-declared).
public enum WidgetStatus: String, Codable, Equatable, Sendable {
    case ok
    case warning
    case error
}

/// What a card action button does when tapped. Deliberately excludes `shell`
/// — see `docs/design/widget-surface-contract.md` §6 — a widget button must
/// not run an arbitrary command without the menu's context.
public enum WidgetActionKind: String, Codable, Equatable, Sendable {
    case refresh
    case href
    case shortcut
}

/// One row in a `list`/`board` template.
public struct WidgetCardItem: Codable, Equatable, Sendable {
    public var label: String
    public var value: String?
    public var symbol: String?
    public var tint: SnapshotColor?

    public init(label: String, value: String? = nil, symbol: String? = nil, tint: SnapshotColor? = nil) {
        self.label = label
        self.value = value
        self.symbol = symbol
        self.tint = tint
    }
}

/// One button rendered on a card (up to two are shown).
public struct WidgetCardAction: Codable, Equatable, Sendable {
    public var kind: WidgetActionKind
    public var label: String
    /// The URL to open, for `kind == .href`.
    public var url: String?
    /// The Shortcut name to run, for `kind == .shortcut`.
    public var name: String?

    public init(kind: WidgetActionKind, label: String, url: String? = nil, name: String? = nil) {
        self.kind = kind
        self.label = label
        self.url = url
        self.name = name
    }
}

/// The rich, structured payload a plugin prints on stdout when invoked with
/// `VEE_TARGET=widget` (see the design doc's "card payload" section). Kept
/// Foundation-only/dependency-free like the rest of `VeeWidgetShared` — the
/// sandboxed widget extension links this module directly.
public struct WidgetCard: Codable, Equatable, Sendable {
    public var template: WidgetTemplate
    public var title: String?
    public var symbol: String?
    public var tint: SnapshotColor?
    public var value: String?
    public var caption: String?
    public var detail: String?
    public var status: WidgetStatus?
    /// `0...1`, clamped by the parser.
    public var progress: Double?
    public var trend: [Double]?
    public var items: [WidgetCardItem]?
    /// Up to two are rendered; the templates decide which.
    public var actions: [WidgetCardAction]?
    /// Seconds; a hint for the next widget reload (like `refreshAfterDate`).
    public var refreshAfter: TimeInterval?
    /// Seconds; when the tile should show a stale treatment.
    public var staleAfter: TimeInterval?

    public init(
        template: WidgetTemplate = .stat,
        title: String? = nil,
        symbol: String? = nil,
        tint: SnapshotColor? = nil,
        value: String? = nil,
        caption: String? = nil,
        detail: String? = nil,
        status: WidgetStatus? = nil,
        progress: Double? = nil,
        trend: [Double]? = nil,
        items: [WidgetCardItem]? = nil,
        actions: [WidgetCardAction]? = nil,
        refreshAfter: TimeInterval? = nil,
        staleAfter: TimeInterval? = nil
    ) {
        self.template = template
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.value = value
        self.caption = caption
        self.detail = detail
        self.status = status
        self.progress = progress
        self.trend = trend
        self.items = items
        self.actions = actions
        self.refreshAfter = refreshAfter
        self.staleAfter = staleAfter
    }

    enum CodingKeys: String, CodingKey {
        case template, title, symbol, tint, value, caption, detail, status, progress, trend, items, actions
        case refreshAfter = "refresh_after"
        case staleAfter = "stale_after"
    }
}
