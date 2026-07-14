import AppKit
import VeePluginFormat

/// A custom menu-row view that draws a plugin's `sparkline=` series inline: the
/// item's label on one side and a small polyline chart on the other. The
/// second in-row rich view after `progress=` (see `ProgressMenuItemView`) —
/// built the same way and for the same reason: pure AppKit, no SwiftUI
/// hosting, so the menu stays native and leak-free. Decorative: it does not
/// intercept clicks, so the row's normal action still fires on click,
/// including the richer Liquid Glass chart popover `sparkline=` also opts
/// into (`AppActionDispatcher` reads `params.sparkline` independently of
/// whichever view the row renders).
final class SparklineMenuItemView: NSView {
    private let title: NSAttributedString
    private let values: [Double]
    private let lineColor: NSColor
    private let layout: ProgressBarLayout

    init(title: NSAttributedString, values: [Double], lineColor: NSColor, chartWidth: CGFloat = 90, chartHeight: CGFloat = 20, leading: Bool = false) {
        self.title = title
        // D9: NaN/Inf would otherwise flow into min()/max() and the point
        // interpolation below, producing garbage geometry. Filter on ingest so
        // `values` is always plottable (or empty) from here on.
        self.values = values.filter { $0.isFinite }
        self.lineColor = lineColor
        let layout = ProgressBarLayout(barWidth: chartWidth, barHeight: chartHeight, leading: leading)
        self.layout = layout
        let rowHeight = Swift.max(22, chartHeight + 10)
        // Size to fit label + chart so the menu grows wide enough, matching
        // ProgressMenuItemView's sizing.
        let titleWidth = title.size().width.rounded(.up)
        let desiredWidth = layout.leadingInset + titleWidth + layout.gap + chartWidth + layout.trailingInset
        super.init(frame: NSRect(x: 0, y: 0, width: Swift.max(240, desiredWidth), height: rowHeight))
        autoresizingMask = [.width]

        // VoiceOver: expose the row's own text/value, same reasoning as
        // ProgressMenuItemView (a custom `NSMenuItem.view` draws its own title
        // and is otherwise silent to VoiceOver).
        setAccessibilityElement(true)
        setAccessibilityLabel(title.string)
        setAccessibilityValue(Self.accessibilitySummary(for: self.values))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if let highlight = menuRowHighlightPath(highlighted: enclosingMenuItem?.isHighlighted ?? false, in: bounds) {
            NSColor.selectedContentBackgroundColor.setFill()
            highlight.fill()
        }

        // `fraction` only matters for progress='s fill rect; the chart uses the
        // track rect as its plotting area and ignores it.
        let rects = layout.rects(in: bounds, fraction: 0)
        title.drawTruncatedCentered(in: rects.label)
        drawChart(in: rects.track)
    }

    /// A concise "latest value + trend" summary read by VoiceOver in place of
    /// the visual chart (e.g. "42, trending up").
    private static func accessibilitySummary(for values: [Double]) -> String {
        guard let last = values.last else { return "No data" }
        guard values.count > 1, let first = values.first else { return format(last) }
        let trend: String
        if last > first { trend = "trending up" } else if last < first { trend = "trending down" } else { trend = "flat" }
        return "\(format(last)), \(trend)"
    }

    // Mirrors SparklineChartView's (VeeUI) footer formatting via the shared
    // trap-safe helper — `String(Int(v))` aborts on |v| ≥ ~9.2e18 and this
    // runs eagerly in `init` on plugin-supplied data.
    private static func format(_ v: Double) -> String {
        CompactNumber.label(v)
    }

    private func drawChart(in chart: CGRect) {
        // D9: nothing finite left to plot (all-NaN/Inf input, or genuinely
        // empty) — skip drawing entirely rather than rendering a misleading
        // baseline for data that was never there.
        guard !values.isEmpty else { return }
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else {
            // Exactly one point can't make a line: draw a flat baseline so the
            // row still reads as "a sparkline slot", not a rendering glitch.
            let path = NSBezierPath()
            path.move(to: CGPoint(x: chart.minX, y: chart.midY))
            path.line(to: CGPoint(x: chart.maxX, y: chart.midY))
            path.lineWidth = 1.5
            lineColor.withAlphaComponent(0.5).setStroke()
            path.stroke()
            return
        }

        let range = hi - lo
        func point(_ index: Int, _ value: Double) -> CGPoint {
            let x = chart.minX + chart.width * CGFloat(index) / CGFloat(values.count - 1)
            // A flat series (range == 0) plots as a centered line, not a
            // divide-by-zero NaN.
            let unit = range > 0 ? (value - lo) / range : 0.5
            return CGPoint(x: x, y: chart.minY + chart.height * CGFloat(unit))
        }

        let line = NSBezierPath()
        let area = NSBezierPath()
        let first = point(0, values[0])
        line.move(to: first)
        area.move(to: first)
        for (index, value) in values.enumerated().dropFirst() {
            let p = point(index, value)
            line.line(to: p)
            area.line(to: p)
        }
        // Close the area down to the baseline, echoing the popover chart's
        // area-under-the-line treatment (`SparklineChartView` in `VeeUI`).
        area.line(to: CGPoint(x: chart.maxX, y: chart.minY))
        area.line(to: CGPoint(x: chart.minX, y: chart.minY))
        area.close()
        lineColor.withAlphaComponent(0.15).setFill()
        area.fill()

        line.lineWidth = 1.5
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        lineColor.setStroke()
        line.stroke()
    }
}
