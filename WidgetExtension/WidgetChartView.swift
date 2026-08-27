import Charts
import SwiftUI
import VeeWidgetShared
import WidgetKit

/// Draws the layout tree's `chart` leaf — the tile-sized twin of a menu row's
/// `pie=` / `donut=` / `stackedbar=`. Native Swift Charts, like the popover the
/// menu opens on click; there is no WebView and no charting library anywhere in
/// Vee.
///
/// A `View` rather than one more case in `LayoutNodeRenderer`'s switch because
/// segment color depends on the *appearance*: a palette slot is a light/dark
/// pair chosen against its own mode's background rather than one color flipped,
/// so it has to be resolved from `@Environment(\.colorScheme)` at draw time —
/// which a static function has no way to read.
///
/// Compact by design, and deliberately not a port of the app's
/// `CategoryChartView`: that one is a popover and can afford a 168pt plot plus a
/// legend row per segment, which is most of a `small` tile. This one sizes the
/// plot per family and shows the legend only where a family has room — the same
/// adaptation-by-subtraction the preset templates use when they truncate rows.
///
/// The tree reaching here is already sanitized app-side by `WidgetCardParser`
/// (kind is one of the three, values finite and non-negative, at most
/// `ChartParams.maxSegments` of them with the tail folded), so this is a plain
/// bounded draw with no validation of its own — same contract as every other
/// leaf in `WidgetNodeView`.
struct WidgetChartView: View {
    let node: WidgetNode
    /// Passed down rather than read from `@Environment(\.widgetFamily)` again:
    /// the walker already resolved the family to apply `families` subtraction,
    /// and the legend has to truncate against the same answer.
    let family: WidgetFamily

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // An empty or all-zero series has no shares to draw. Rendering nothing
        // beats reserving plot height for a blank circle; the parser already
        // logged whatever produced it.
        if !segments.isEmpty, total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                plot
                legend
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilitySummary)
        }
    }

    // MARK: - Plot

    @ViewBuilder
    private var plot: some View {
        switch node.kind {
        case "pie": radial(innerRadius: 0)
        case "donut": radial(innerRadius: Self.donutInnerRatio)
        case "stackedbar": stackedBar
        default:
            // Unreachable for a parsed card (an unknown kind drops the whole
            // leaf, with a diagnostic). Drawing nothing rather than guessing is
            // what `LayoutNodeRenderer` does for an unknown node type.
            EmptyView()
        }
    }

    /// A pie (`innerRadius: 0`) or a donut, as sectors. `angularInset` is the
    /// popover's surface gap: it makes the boundary legible and doubles as the
    /// secondary encoding that keeps neighbouring hues apart for a reader who
    /// cannot tell them by color.
    private func radial(innerRadius: Double) -> some View {
        Chart(segments) { segment in
            SectorMark(
                angle: .value("Share", segment.value),
                innerRadius: .ratio(innerRadius),
                angularInset: Self.segmentGap / 2
            )
            .cornerRadius(2)
            .foregroundStyle(segment.color)
        }
        // The legend below is built by hand so unlabelled segments read
        // correctly; Chart's own legend shows only what a style scale knows.
        .chartLegend(.hidden)
        .frame(height: Self.radialHeight(for: family))
    }

    /// One 100%-wide bar of end-to-end segments. Bars sharing a category
    /// position stack, so a mark per segment *is* the stacked bar; the capsule
    /// clip gives it the same silhouette a `progress=` bar has.
    private var stackedBar: some View {
        Chart(segments) { segment in
            BarMark(
                x: .value("Share", segment.value),
                y: .value("Chart", ""),
                height: .fixed(Self.barThickness)
            )
            .foregroundStyle(segment.color)
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: Self.barThickness)
        .clipShape(Capsule())
    }

    // MARK: - Legend

    /// Swatch · name, one row per *named* segment — the popover's legend minus
    /// the share percentages a tile has no width for. A chart with no
    /// `labels` gets none at all: "Segment 1, Segment 2" is chrome, not data.
    ///
    /// Truncated per family with the very numbers `ListCardView` uses for its
    /// rows (large ≤8, medium ≤3, small none), so a chart drops its legend
    /// exactly where a list drops its rows.
    @ViewBuilder
    private var legend: some View {
        let named = segments.filter { $0.label != nil }.prefix(legendLimit)
        if !named.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(named) { segment in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(segment.color)
                            .frame(width: 7, height: 7)
                        Text(segment.label ?? "")
                            .font(.caption2)
                            .foregroundStyle(node.style?.tint?.swiftUIColor ?? .secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var legendLimit: Int {
        switch family {
        case .systemSmall: return 0
        case .systemLarge, .systemExtraLarge: return 8
        default: return 3
        }
    }

    // MARK: - Data

    private var total: Double { (node.values ?? []).reduce(0, +) }

    private var segments: [Segment] {
        let values = node.values ?? []
        return values.indices.map { index in
            Segment(id: index, value: values[index], label: label(at: index), color: color(at: index))
        }
    }

    /// The plugin's name for a segment, if it gave one. Positional and allowed
    /// to be shorter than `values`, exactly like `ChartParams.labels`.
    private func label(at index: Int) -> String? {
        guard let labels = node.labels, labels.indices.contains(index), !labels[index].isEmpty else { return nil }
        return labels[index]
    }

    /// A declared `colors` entry wins; anything past the end of that list — the
    /// usual case, since `colors` recolors a prefix — takes the segment's
    /// palette slot for the active appearance. Same precedence
    /// `ChartColorResolver` and `ChartSegmentColor` apply on the menu surfaces.
    private func color(at index: Int) -> Color {
        if let colors = node.colors, colors.indices.contains(index) {
            return colors[index].swiftUIColor
        }
        return WidgetChartPalette.slot(at: index, dark: colorScheme == .dark)
    }

    /// "Documents 45%, Photos 30%, …" — the spoken summary every surface that
    /// draws a share chart attaches (`ChartParams.accessibilitySummary`),
    /// restated here because the extension cannot see `VeePluginFormat`. Color
    /// is never the only channel the data survives on.
    private var accessibilitySummary: String {
        segments.map { segment in
            let share = Int((segment.value / total * 100).rounded())
            return "\(segment.label ?? "Segment \(segment.id + 1)") \(share)%"
        }.joined(separator: ", ")
    }

    private struct Segment: Identifiable {
        let id: Int
        let value: Double
        let label: String?
        let color: Color
    }

    // MARK: - Metrics

    /// The donut hole as a share of the outer radius, and the gap between
    /// adjacent segments in points — both the app popover's numbers, so the two
    /// surfaces draw the same shape from the same series.
    ///
    /// The hole stays empty here: the popover centres the total in it, which
    /// needs a compact-number formatter that lives app-side, and a tile's hole
    /// is a few points across.
    private static let donutInnerRatio: Double = 0.58
    private static let segmentGap: Double = 2

    /// Bar thickness, matching `ChartParams.defaultBarHeight` — the same visual
    /// weight `progress=` has, on the menu and on the tile.
    private static let barThickness: CGFloat = 12

    /// A radial plot's height, per family: the largest circle that still leaves
    /// the rest of the tree room to breathe. A circle's width is its diameter,
    /// so height is the only knob — the same reason `chartw=full` is refused on
    /// a menu pie.
    private static func radialHeight(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall: return 56
        case .systemLarge, .systemExtraLarge: return 96
        default: return 72
        }
    }
}

/// The eight categorical slots a chart's segments take when the plugin names no
/// colors of its own.
///
/// A literal restatement of `ChartPalette.slots` (`VeePluginFormat`), for the
/// same reason `SnapshotColor` restates `VeeColor`: the sandboxed extension
/// links only `VeeWidgetShared`, which is Foundation-only and pulls in nothing.
/// Because both sides are explicit sRGB, a segment with no declared color comes
/// out identical on the menu row, the popover and the tile.
///
/// Slots are assigned in order and never cycled — slot *n* always means "the
/// nth segment", so a series that shrinks does not repaint the segments that
/// survived. Each is a light/dark *pair* selected against its own mode's
/// background rather than one color flipped, and the set is validated for
/// colorblind separation including the first-to-last pair, which a pie makes
/// adjacent by wrapping around. Keep the two lists in step: the parity ledger
/// records the widget's chart as supported *because* it draws the menu's chart.
private enum WidgetChartPalette {
    /// `ChartPalette.slots` in wire form — blue, orange, aqua, yellow, magenta,
    /// green, violet, red — reusing `SnapshotColor`'s own hex grammar rather
    /// than restating channel arithmetic a second time.
    private static let slots: [(light: Color, dark: Color)] = [
        ("#2a78d6", "#3987e5"), ("#eb6834", "#d95926"),
        ("#1baf7a", "#199e70"), ("#eda100", "#c98500"),
        ("#e87ba4", "#d55181"), ("#008300", "#008300"),
        ("#4a3aa7", "#9085e9"), ("#e34948", "#e66767")
    ].map { (color($0.0), color($0.1)) }

    /// The color for slot `index` on the active appearance. Indices are clamped
    /// rather than cycled; the parser's eight-segment fold keeps callers inside
    /// the range anyway.
    static func slot(at index: Int, dark: Bool) -> Color {
        let pair = slots[max(0, min(index, slots.count - 1))]
        return dark ? pair.dark : pair.light
    }

    private static func color(_ hex: String) -> Color {
        SnapshotColor.parse(hex)?.swiftUIColor ?? .accentColor
    }
}
