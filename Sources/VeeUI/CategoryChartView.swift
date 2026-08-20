import AppKit
import Charts
import SwiftUI
import VeePluginFormat

/// Renders a plugin's `pie=`/`donut=`/`stackedbar=` chart as a Liquid Glass
/// popover — the richer counterpart to the small inline chart the menu row
/// itself draws (`CategoryChartMenuItemView` in `VeeMenu`). Native Swift Charts,
/// no WebView, and the same card idiom as `SparklineChartView`/
/// `PluginControlView` so the popover kinds read as one family.
///
/// Every segment is direct-labelled in a legend with its share, so the chart is
/// never read by color alone — the popover is where a plugin's segment names
/// (`chartlabels=`) actually become visible, since a menu row has no space for
/// them.
public struct CategoryChartView: View {
    private let chart: ChartParams
    private let title: String
    private let onDetach: (() -> Void)?

    /// `onDetach` is supplied by the popover host to offer "open in a window";
    /// the detached window renders the same view without it, since there is
    /// nothing left to detach.
    public init(chart: ChartParams, title: String = "", onDetach: (() -> Void)? = nil) {
        self.chart = chart
        self.title = title
        self.onDetach = onDetach
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title).font(.headline).lineLimit(1)
            }
            plot
            legend
        }
        .padding(14)
        .frame(minWidth: 240, minHeight: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Corner.popover, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(chart.accessibilitySummary())
        // Outside the combined element above, so the button stays its own
        // VoiceOver target instead of being folded into the chart's summary.
        .overlay(alignment: .topTrailing) {
            if let onDetach { DetachButton(action: onDetach) }
        }
    }

    // MARK: - Plot

    @ViewBuilder
    private var plot: some View {
        switch chart.kind {
        case .pie: radial(innerRadius: 0)
        case .donut: radial(innerRadius: Self.donutInnerRatio)
        case .stackedBar: stackedBar
        }
    }

    /// Donut hole, as a share of the outer radius — the same ratio the inline
    /// menu-row chart uses, so the two surfaces draw the same shape.
    private static let donutInnerRatio: Double = 0.58
    /// Surface gap between adjacent segments, in points. Matches the inline
    /// row view: it makes the boundary legible and doubles as the secondary
    /// encoding that keeps neighbouring hues apart.
    private static let segmentGap: Double = 2

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
        // The legend below is built by hand so unlabelled segments and the
        // folded "Other" slice read correctly; Chart's own legend would show
        // only what a style scale knows about.
        .chartLegend(.hidden)
        .frame(height: 108)
        .overlay {
            if chart.kind == .donut {
                VStack(spacing: 0) {
                    Text(CompactNumber.label(chart.total))
                        .font(.headline).monospacedDigit()
                    Text("total").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A single 100%-wide bar of end-to-end segments. Laid out directly rather
    /// than as a `BarMark` stack: the segments need an exact surface gap between
    /// them and a capsule clip, which is the same treatment `progress=` and the
    /// inline row chart get.
    private var stackedBar: some View {
        GeometryReader { geometry in
            let gaps = Self.segmentGap * Double(max(0, segments.count - 1))
            let usable = max(0, Double(geometry.size.width) - gaps)
            HStack(spacing: Self.segmentGap) {
                ForEach(segments) { segment in
                    segment.color
                        .frame(width: usable * chart.fraction(at: segment.id))
                }
            }
            .frame(height: geometry.size.height, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: 22)
    }

    // MARK: - Legend

    /// Swatch · name · share, one row per segment. Text stays in the standard
    /// ink colors — the swatch beside it is what carries identity.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(segments) { segment in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(segment.color)
                        .frame(width: 9, height: 9)
                    Text(segment.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.percent(chart.fraction(at: segment.id)))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Data

    private var segments: [Segment] {
        chart.values.indices.map { index in
            Segment(
                id: index,
                value: chart.values[index],
                name: chart.label(at: index) ?? "Segment \(index + 1)",
                color: ChartSegmentColor.color(for: chart, at: index)
            )
        }
    }

    private struct Segment: Identifiable {
        let id: Int
        let value: Double
        let name: String
        let color: Color
    }
}

/// Resolves one chart segment to the SwiftUI `Color` the popover draws it with.
///
/// Deliberately parallel to `ChartColorResolver` in `VeeMenu` rather than shared
/// with it: that one produces `NSColor` for AppKit drawing and resolves AppKit's
/// semantic colors, this one produces SwiftUI `Color` and resolves SwiftUI's.
/// `VeeUI` does not (and should not) depend on the menu layer for a leaf color
/// utility. Palette slots are explicit sRGB in both, so a segment with no
/// `chartcolors=` override is byte-identical across the two surfaces.
enum ChartSegmentColor {
    static func color(for chart: ChartParams, at index: Int) -> Color {
        if let override = chart.colorOverride(at: index), let resolved = color(for: override) {
            return resolved
        }
        // Palette slots are selected per surface, so resolve at draw time from
        // the active appearance rather than picking one column up front.
        let light = chart.paletteColor(at: index, surface: .light)
        let dark = chart.paletteColor(at: index, surface: .dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(for: isDark ? dark : light) ?? .controlAccentColor
        })
    }

    private static func color(for veeColor: VeeColor) -> Color? {
        switch veeColor {
        case .rgb(let r, let g, let b, let a):
            return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
        case .named(let name):
            return named[name.replacingOccurrences(of: " ", with: "")]
        }
    }

    private static func nsColor(for veeColor: VeeColor) -> NSColor? {
        guard case .rgb(let r, let g, let b, let a) = veeColor else { return nil }
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    /// The same names `ColorResolver` (VeeMenu) accepts, mapped onto SwiftUI's
    /// own system/semantic colors.
    private static let named: [String: Color] = [
        "black": .black, "white": .white, "red": .red, "green": .green,
        "blue": .blue, "yellow": .yellow, "orange": .orange,
        "purple": .purple, "pink": .pink, "brown": .brown,
        "gray": .gray, "grey": .gray, "cyan": .cyan, "teal": .teal,
        "indigo": .indigo, "magenta": Color(nsColor: .magenta), "clear": .clear,
        "labelcolor": .primary, "secondarylabelcolor": .secondary,
        "tertiarylabelcolor": Color(nsColor: .tertiaryLabelColor), "linkcolor": Color(nsColor: .linkColor),
        "controlaccentcolor": .accentColor
    ]
}
