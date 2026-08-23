import Foundation

/// Which shape a row's categorical chart takes (`pie=` / `donut=` /
/// `stackedbar=`). All three describe the *same* data — one series of
/// non-negative category values read as shares of a whole — so they share a
/// single parsed model (`ChartParams`) and differ only in how a renderer draws
/// it. That is deliberate: a plugin can switch `pie=` to `stackedbar=` without
/// touching its numbers, labels, or colors.
public enum ChartKind: String, Equatable, Sendable, CaseIterable {
    /// A filled circle divided into sectors.
    case pie
    /// A pie with the middle punched out; the hole carries the total.
    case donut
    /// A single horizontal bar whose segments are laid end to end.
    case stackedBar = "stackedbar"
}

/// A Vee-native categorical chart attached to a menu row (`pie=`/`donut=`/
/// `stackedbar=`), rendered natively — an AppKit row view in the menu and a
/// Swift Charts popover on click, no WebView anywhere.
///
/// Invariants established at parse time and relied on by every renderer:
/// * `values` is non-empty, every element is finite and `>= 0`, and `total > 0`
///   (an all-zero series has no shares to draw, so it never becomes a chart).
/// * `values.count <= ChartParams.maxSegments`. A longer series is folded — not
///   truncated — by the parser: the leading segments are kept and the rest are
///   summed into a final "Other" segment, so the shares still add up to the
///   plugin's own total.
/// * `labels`/`colors` are advisory and may be shorter (or empty) than
///   `values`; use `label(at:)`/`color(at:)`, which fall back to the shared
///   `ChartPalette`.
public struct ChartParams: Equatable, Sendable {
    /// The most segments a chart will ever carry. Eight is the categorical
    /// palette's full length (see `ChartPalette`) — past it, hues would have to
    /// be cycled and two slices would share a color, which is exactly the
    /// ambiguity a share chart must not have.
    public static let maxSegments = 8

    /// Label used for the aggregated tail when a series is folded to fit
    /// `maxSegments`, unless the plugin labelled that slot itself.
    public static let otherLabel = "Other"

    public var kind: ChartKind
    /// Segment magnitudes, in draw order. Never empty; always finite and `>= 0`.
    public var values: [Double]
    /// Per-segment names (`chartlabels=`). May be shorter than `values`.
    public var labels: [String]
    /// Per-segment color overrides (`chartcolors=`), positional against
    /// `values`. May be shorter than `values`, and an entry may be `nil` —
    /// either the plugin left that slot blank or its color was malformed. A
    /// missing entry takes the segment's `ChartPalette` slot, so a partial list
    /// like `chartcolors=,,red` recolors only the third segment instead of
    /// sliding every later color one position to the left.
    public var colors: [VeeColor?]
    /// True when the parser folded a too-long series into a trailing "Other"
    /// segment, so renderers can mark that slice as an aggregate.
    public var isFolded: Bool
    /// Declared inline size (`chartw=`/`charth=`), in points, or `nil` for the
    /// per-kind default. Clamped at parse time; see `sizeLimit`.
    public var width: Double?
    public var height: Double?
    /// `chartw=full`: the chart stretches to whatever width the row actually
    /// has, instead of a fixed number of points. A menu is as wide as its
    /// widest row, so a fixed width can't fill a menu whose width some *other*
    /// row decides — this can. The chart takes the row's content width, less
    /// the row's own text when it has any.
    ///
    /// Only ever true for `.stackedBar`: `full` is a *width* control, and a
    /// circle has no free width — its width is its diameter, so stretching one
    /// into a row's leftover space would make the row as tall as the menu is
    /// wide. `make` drops it (with a diagnostic) on `.pie`/`.donut`, which are
    /// sized by `chartw=`/`charth=` points instead. Same rule as the widget
    /// layout tree, where `style.fill` grows a node to the available *width*
    /// and a circular gauge takes no size knob at all.
    public var isFullWidth: Bool

    public init(
        kind: ChartKind,
        values: [Double],
        labels: [String] = [],
        colors: [VeeColor?] = [],
        isFolded: Bool = false,
        width: Double? = nil,
        height: Double? = nil,
        isFullWidth: Bool = false
    ) {
        self.kind = kind
        self.values = values
        self.labels = labels
        self.colors = colors
        self.isFolded = isFolded
        self.width = width
        self.height = height
        self.isFullWidth = isFullWidth
    }

    /// The inline slot a chart occupies in a menu row, in points.
    ///
    /// Lives here, in the format layer, for the same reason `ProgressParams`'
    /// bar dimensions do: both the AppKit menu row (`VeeMenu`) and the SwiftUI
    /// window row (`VeeUI`) apply it, they cannot see each other's modules, and
    /// a chart that measured differently on the two surfaces would be exactly
    /// the drift this avoids by construction.
    public var inlineSize: (width: Double, height: Double) {
        switch kind {
        case .pie, .donut:
            // A circle: one declared dimension sizes both, so `charth=40` on a
            // pie does what it looks like it does.
            let side = height ?? width ?? Self.defaultCircleSide
            return (side, side)
        case .stackedBar:
            return (width ?? Self.defaultBarWidth, height ?? Self.defaultBarHeight)
        }
    }

    /// Default inline dimensions, in points. The circle is larger than a text
    /// row's cap height on purpose — at line height a pie reads as a dot, not a
    /// chart — and the bar matches `progress=`'s visual weight.
    public static let defaultCircleSide: Double = 24
    public static let defaultBarWidth: Double = 110
    public static let defaultBarHeight: Double = 12
    /// `chartw=`/`charth=` are clamped to this range. A menu row grows to fit
    /// its accessory, so an unclamped value is a plugin that can push rows off
    /// the screen; the ceiling is generous enough for a chart that dominates a
    /// row and still fits a dropdown.
    public static let sizeLimit: ClosedRange<Double> = 8...200

    /// The sum of every segment. Guaranteed `> 0` for a parsed chart.
    public var total: Double { values.reduce(0, +) }

    /// Segment `index`'s share of the total, in `0...1`. Returns `0` for an
    /// out-of-range index or a degenerate total rather than a NaN, so geometry
    /// math downstream can never produce garbage.
    public func fraction(at index: Int) -> Double {
        guard values.indices.contains(index) else { return 0 }
        let sum = total
        guard sum > 0, sum.isFinite else { return 0 }
        return values[index] / sum
    }

    /// The plugin's label for segment `index`, if it gave one. The folded tail
    /// falls back to "Other" so an aggregated slice always reads as aggregate.
    public func label(at index: Int) -> String? {
        if labels.indices.contains(index), !labels[index].isEmpty { return labels[index] }
        if isFolded, index == values.count - 1 { return Self.otherLabel }
        return nil
    }

    /// The plugin's own color for segment `index`, if it named one. Renderers
    /// need this separately from `color(at:surface:)` because an override is a
    /// single fixed color, while a palette slot is a light/dark pair they resolve
    /// dynamically.
    public func colorOverride(at index: Int) -> VeeColor? {
        colors.indices.contains(index) ? colors[index] : nil
    }

    /// The color for segment `index` on `surface`: the plugin's `chartcolors=`
    /// entry when it supplied one, the neutral for a folded "Other" tail,
    /// otherwise that position's palette slot stepped for the surface.
    ///
    /// The one place segment color is decided, so the menu row, the popover, and
    /// the CLI can't drift apart on what a series looks like.
    public func color(at index: Int, surface: ChartSurface = .light) -> VeeColor {
        colorOverride(at: index) ?? paletteColor(at: index, surface: surface)
    }

    /// Segment `index`'s color ignoring any `chartcolors=` override: the neutral
    /// for a folded "Other" tail, otherwise that position's palette slot. This
    /// is what a renderer falls back to when an override names a color it can't
    /// resolve — a segment must still get a color that means "position n", never
    /// a generic accent that collides with its neighbours.
    public func paletteColor(at index: Int, surface: ChartSurface = .light) -> VeeColor {
        if isFolded, index == values.count - 1 { return ChartPalette.other }
        return ChartPalette.slot(at: index, surface: surface)
    }

    /// Builds a chart from already-numeric input, applying every invariant the
    /// renderers rely on and reporting what it had to change. Shared by the text
    /// parser (`pie=`/`donut=`/`stackedbar=`) and the structured-JSON parser
    /// (`"chart"`) so both produce an identical model from equivalent input —
    /// the same reason the rich params validate in one place today.
    ///
    /// Returns `nil` (with a diagnostic) when the series can't be drawn as
    /// shares at all: empty, non-finite, negative, or summing to zero.
    public static func make(
        kind: ChartKind,
        values: [Double],
        labels: [String] = [],
        colors: [VeeColor?] = [],
        width: Double? = nil,
        height: Double? = nil,
        isFullWidth: Bool = false,
        diagnostics: inout [ParseDiagnostic]
    ) -> ChartParams? {
        guard !values.isEmpty else {
            diagnostics.append(.init(
                severity: .warning,
                message: "\(kind.rawValue)= expects a comma-separated list of non-negative numbers"
            ))
            return nil
        }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            diagnostics.append(.init(
                severity: .warning,
                message: "\(kind.rawValue)= values must all be finite and non-negative"
            ))
            return nil
        }
        // Every share would be 0/0. Drawing nothing is right, but silently is
        // not — an all-zero series is usually a plugin bug, not a design.
        guard values.reduce(0, +) > 0 else {
            diagnostics.append(.init(
                severity: .warning,
                message: "\(kind.rawValue)= values sum to zero; nothing to chart"
            ))
            return nil
        }

        // `full` stretches an accessory across the row's leftover width. A
        // pie/donut fills that width only by growing its diameter — i.e. by
        // growing the row to match — so it is refused here rather than at each
        // renderer: dropping it once in the model is what keeps the AppKit menu
        // row, the SwiftUI window row, and the CLI from each inventing their own
        // answer (they did: the menu centred the circle in the stretched slot,
        // the window ignored the flag entirely).
        var fullWidth = isFullWidth
        if fullWidth, kind != .stackedBar {
            diagnostics.append(.init(
                severity: .warning,
                message: "chartw=full applies to stackedbar=; size a \(kind.rawValue)= with chartw=/charth= points"
            ))
            fullWidth = false
        }

        var outValues = values
        var outLabels = labels
        var outColors = colors
        var folded = false

        if values.count > maxSegments {
            // Fold, don't truncate: these values are read as shares of a whole,
            // so dropping the tail would silently re-scale every slice that
            // survived. Summing it into "Other" keeps the total honest.
            let kept = maxSegments - 1
            let remainder = values[kept...].reduce(0, +)
            diagnostics.append(.init(
                severity: .warning,
                message: "\(kind.rawValue)= has \(values.count) segments; the last \(values.count - kept) were folded into '\(otherLabel)'"
            ))
            outValues = Array(values.prefix(kept)) + [remainder]
            // Trim the plugin's labels/colors to the kept segments so the folded
            // slot falls back to "Other" and the neutral color rather than
            // inheriting whatever happened to sit at that index.
            outLabels = Array(labels.prefix(kept))
            outColors = Array(colors.prefix(kept))
            folded = true
        }

        return ChartParams(
            kind: kind,
            values: outValues,
            labels: Array(outLabels.prefix(outValues.count)),
            colors: Array(outColors.prefix(outValues.count)),
            isFolded: folded,
            width: width.map { Swift.min(Swift.max($0, sizeLimit.lowerBound), sizeLimit.upperBound) },
            height: height.map { Swift.min(Swift.max($0, sizeLimit.lowerBound), sizeLimit.upperBound) },
            isFullWidth: fullWidth
        )
    }

    /// A spoken description of the whole chart — "Documents 45%, Photos 30%, …"
    /// — used as the accessibility value of every surface that draws one, so the
    /// data is never conveyed by color alone.
    public func accessibilitySummary() -> String {
        guard !values.isEmpty else { return "No data" }
        return values.indices.map { (index: Int) -> String in
            let share = Int((fraction(at: index) * 100).rounded())
            if let name = label(at: index) { return "\(name) \(share)%" }
            return "Segment \(index + 1) \(share)%"
        }.joined(separator: ", ")
    }
}

/// Which surface a chart is being drawn on. Palette slots are *selected* per
/// surface rather than one set of colors flipped for dark mode, so every
/// renderer has to say which one it is drawing for.
public enum ChartSurface: Equatable, Sendable {
    case light
    case dark
}

/// The categorical color palette Vee draws chart segments with when a plugin
/// doesn't name its own (`chartcolors=`).
///
/// Eight fixed slots, assigned in order and never cycled — slot *n* always means
/// "the nth segment", so a plugin whose series shrinks doesn't repaint the
/// survivors. Each slot is a light/dark pair rather than one color: the values
/// were selected per mode against that mode's surface, not flipped, and the set
/// was validated for colorblind separation (worst adjacent CVD ΔE 9.1 light /
/// 8.4 dark on the OKLab×100 scale, ≥8 target; worst adjacent normal-vision ΔE
/// 19.6 / 19.3, ≥15 floor) including the first↔last pair, which a pie chart
/// makes adjacent by wrapping around.
///
/// Kept here in `VeePluginFormat` — AppKit- and SwiftUI-free, expressed as plain
/// `VeeColor` — so the menu row view, the Swift Charts popover, and the CLI's
/// truecolor terminal output all draw the *same* series in the same colors.
public enum ChartPalette {
    /// One categorical slot: the same hue stepped for each surface.
    public struct Slot: Equatable, Sendable {
        public let light: VeeColor
        public let dark: VeeColor

        public init(light: VeeColor, dark: VeeColor) {
            self.light = light
            self.dark = dark
        }
    }

    /// The eight slots, in assignment order: blue, orange, aqua, yellow,
    /// magenta, green, violet, red.
    public static let slots: [Slot] = [
        Slot(light: .rgb(r: 0x2a, g: 0x78, b: 0xd6, a: 255), dark: .rgb(r: 0x39, g: 0x87, b: 0xe5, a: 255)),
        Slot(light: .rgb(r: 0xeb, g: 0x68, b: 0x34, a: 255), dark: .rgb(r: 0xd9, g: 0x59, b: 0x26, a: 255)),
        Slot(light: .rgb(r: 0x1b, g: 0xaf, b: 0x7a, a: 255), dark: .rgb(r: 0x19, g: 0x9e, b: 0x70, a: 255)),
        Slot(light: .rgb(r: 0xed, g: 0xa1, b: 0x00, a: 255), dark: .rgb(r: 0xc9, g: 0x85, b: 0x00, a: 255)),
        Slot(light: .rgb(r: 0xe8, g: 0x7b, b: 0xa4, a: 255), dark: .rgb(r: 0xd5, g: 0x51, b: 0x81, a: 255)),
        Slot(light: .rgb(r: 0x00, g: 0x83, b: 0x00, a: 255), dark: .rgb(r: 0x00, g: 0x83, b: 0x00, a: 255)),
        Slot(light: .rgb(r: 0x4a, g: 0x3a, b: 0xa7, a: 255), dark: .rgb(r: 0x90, g: 0x85, b: 0xe9, a: 255)),
        Slot(light: .rgb(r: 0xe3, g: 0x49, b: 0x48, a: 255), dark: .rgb(r: 0xe6, g: 0x67, b: 0x67, a: 255))
    ]

    /// The deliberate neutral for a folded "Other" segment. Low chroma is the
    /// point — it reads as "the remainder", not as a ninth category — so it sits
    /// outside `slots` and is never handed out by `slot(at:)`.
    public static let other: VeeColor = .rgb(r: 0x8a, g: 0x8a, b: 0x85, a: 255)

    /// The color for slot `index` on `surface`. Indices are clamped into range
    /// rather than cycled; `ChartParams.maxSegments` keeps callers inside it.
    public static func slot(at index: Int, surface: ChartSurface = .light) -> VeeColor {
        let pair = slotPair(at: index)
        return surface == .dark ? pair.dark : pair.light
    }

    /// The light/dark pair for slot `index`, for renderers that can resolve a
    /// dynamic color (AppKit, SwiftUI).
    public static func slotPair(at index: Int) -> Slot {
        let bounded = Swift.max(0, Swift.min(index, slots.count - 1))
        return slots[bounded]
    }
}
