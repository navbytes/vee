import Foundation

/// A node in a card's optional **layout tree** — the composable escape hatch
/// alongside the five preset templates (`WidgetTemplate`). A plugin that needs
/// a layout the presets can't express (two columns, a date rail, activity
/// rings, a KPI grid) emits a `layout` tree instead of picking a `template`;
/// the widget extension walks it into native SwiftUI (`WidgetNodeView`). See
/// `docs/design/widget-surface-contract.md` §"Layout tree".
///
/// Deliberately *bounded*, not freeform: a small, fixed vocabulary of
/// containers and leaves that each map 1:1 to a SwiftUI primitive, so the
/// renderer stays trivial and leak-free. No absolute positioning, no point
/// frames, no scroll views — that boundary is what keeps this from becoming the
/// WebView canvas Vee rejects.
///
/// `type` is decoded as a plain string (not a strict enum) so an unknown node
/// type degrades to a diagnostic in `WidgetCardParser` instead of failing the
/// whole card decode — the same tolerance the parser already applies to
/// `template`/`status`. Unknown keys are ignored (forward-compatible).
///
/// Foundation-only like the rest of `VeeWidgetShared`; the sandboxed extension
/// links this module and must pull in almost nothing.
public struct WidgetNode: Codable, Equatable, Sendable {
    /// The node kind: `vstack` / `hstack` / `zstack` / `grid` (containers) or
    /// `text` / `image` / `gauge` / `sparkline` / `chart` / `spacer` /
    /// `divider` (leaves).
    /// Properties and `init` follow the canonical wire order the SDKs emit
    /// (leaf fields, then container layout, then `children` last) so authoring
    /// a tree by hand reads top-down.
    public var type: String

    // Leaves.
    /// The string for a `text` node.
    public var text: String?
    /// The SF Symbol name for an `image` node (v1 renders SF Symbols only).
    public var symbol: String?
    /// The `0…1` fill for a `gauge` node (clamped by the parser).
    public var value: Double?
    /// The series for a `sparkline` node, or the segment magnitudes for a
    /// `chart` node — one series field, because a node is only ever one leaf.
    /// Non-finite entries are dropped and the count capped by the parser, per
    /// kind (a trend takes hundreds of points, a share chart eight segments).
    public var values: [Double]?
    /// `linear` (default) or `circular`, for a `gauge` node.
    public var gaugeStyle: String?
    /// The shape of a `chart` node: `pie` / `donut` / `stackedbar` — the same
    /// three spellings `pie=`/`donut=`/`stackedbar=` take on a menu row, so one
    /// series means the same thing on both surfaces. An unrecognized kind drops
    /// the leaf (with a diagnostic) in `WidgetCardParser`.
    ///
    /// Spelled bare rather than `chart_kind`: bare leaf-field names are this
    /// file's convention (`text`, `symbol`, `value`, `values`) and `type:
    /// "chart"` already scopes it — `gauge_style` carries a prefix only because
    /// `style` is taken by the modifier object.
    public var kind: String?
    /// Per-segment names for a `chart` node. Advisory and positional: it may be
    /// shorter than `values`, exactly like `ChartParams.labels` on the menu.
    public var labels: [String]?
    /// Per-segment color overrides for a `chart` node (the `chartcolors=` twin),
    /// positional against `values` and likewise allowed to be shorter — a
    /// segment with no entry takes the renderer's palette slot for its position.
    public var colors: [SnapshotColor]?

    // Containers.
    /// Cross-axis alignment for a stack (`leading`/`center`/`trailing` on
    /// v/z-stacks, `top`/`center`/`bottom` on h-stacks). Interpreted by the walker.
    public var align: String?
    /// Inter-child spacing, in points (clamped by the parser).
    public var spacing: Double?
    /// Column count for `grid` (defaults to 2; clamped 1…4 by the parser).
    public var columns: Int?
    /// The minimum length for a `spacer` node.
    public var minLength: Double?

    /// Widget families this node renders in (`small`/`medium`/`large`). Absent
    /// = all families. Lets one tree adapt by subtraction instead of authoring
    /// three payloads (mirrors how the preset templates truncate per family).
    public var families: [String]?

    /// Per-element styling.
    public var style: WidgetNodeStyle?

    /// Child nodes, for the container types.
    public var children: [WidgetNode]?

    public init(
        type: String,
        text: String? = nil,
        symbol: String? = nil,
        value: Double? = nil,
        values: [Double]? = nil,
        gaugeStyle: String? = nil,
        kind: String? = nil,
        labels: [String]? = nil,
        colors: [SnapshotColor]? = nil,
        align: String? = nil,
        spacing: Double? = nil,
        columns: Int? = nil,
        minLength: Double? = nil,
        families: [String]? = nil,
        style: WidgetNodeStyle? = nil,
        children: [WidgetNode]? = nil
    ) {
        self.type = type
        self.text = text
        self.symbol = symbol
        self.value = value
        self.values = values
        self.gaugeStyle = gaugeStyle
        self.kind = kind
        self.labels = labels
        self.colors = colors
        self.align = align
        self.spacing = spacing
        self.columns = columns
        self.minLength = minLength
        self.families = families
        self.style = style
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case type, text, symbol, value, values, kind, labels, colors, align, spacing, columns, families, style, children
        case gaugeStyle = "gauge_style"
        case minLength = "min_length"
    }
}

/// The bounded set of per-element modifiers a `WidgetNode` can carry. Each maps
/// to a SwiftUI modifier that is cheap and can't push the layout toward
/// freeform drawing. Numeric values are clamped by `WidgetCardParser`.
public struct WidgetNodeStyle: Codable, Equatable, Sendable {
    public var font: WidgetNodeFont?
    /// A named (`green`, `secondary`) or `#rrggbbaa` color; reuses `SnapshotColor`.
    public var tint: SnapshotColor?
    /// Multiline text alignment (`leading`/`center`/`trailing`).
    public var align: String?
    /// Uniform padding in points (clamped 0…64).
    public var padding: Double?
    /// Maximum text lines (clamped 1…20).
    public var lineLimit: Int?
    /// `monospacedDigit()` — keeps numeric columns from jittering (a preset
    /// value uses this; the tree needs it for parity).
    public var monospacedDigit: Bool?
    /// `minimumScaleFactor` — lets a headline shrink to fit rather than
    /// truncate (clamped 0.3…1.0; a preset value uses 0.6).
    public var minScale: Double?
    /// Grow to fill the available width (`frame(maxWidth: .infinity)`); the
    /// only, bounded, width control — arbitrary point frames are not exposed.
    public var fill: Bool?

    public init(
        font: WidgetNodeFont? = nil,
        tint: SnapshotColor? = nil,
        align: String? = nil,
        padding: Double? = nil,
        lineLimit: Int? = nil,
        monospacedDigit: Bool? = nil,
        minScale: Double? = nil,
        fill: Bool? = nil
    ) {
        self.font = font
        self.tint = tint
        self.align = align
        self.padding = padding
        self.lineLimit = lineLimit
        self.monospacedDigit = monospacedDigit
        self.minScale = minScale
        self.fill = fill
    }

    enum CodingKeys: String, CodingKey {
        case font, tint, align, padding, fill
        case lineLimit = "line_limit"
        case monospacedDigit = "monospaced_digit"
        case minScale = "min_scale"
    }
}

/// A text node's font. `size` is a semantic token (`caption2`…`largeTitle`);
/// `pointSize` is an explicit size (clamped 8…96) for the cases a semantic
/// token can't hit (a big number, a small legend). When both are present the
/// renderer prefers `pointSize`.
public struct WidgetNodeFont: Codable, Equatable, Sendable {
    public var size: String?
    public var pointSize: Double?
    public var weight: String?
    public var design: String?

    public init(size: String? = nil, pointSize: Double? = nil, weight: String? = nil, design: String? = nil) {
        self.size = size
        self.pointSize = pointSize
        self.weight = weight
        self.design = design
    }

    enum CodingKeys: String, CodingKey {
        case size, weight, design
        case pointSize = "point_size"
    }
}
