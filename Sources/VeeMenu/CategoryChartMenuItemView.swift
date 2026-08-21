import AppKit
import VeePluginFormat

/// A custom menu-row view that draws a plugin's `pie=`/`donut=`/`stackedbar=`
/// chart inline: the item's label on one side and the chart on the other. The
/// third in-row rich view, after `progress=` and `sparkline=` (see
/// `ProgressMenuItemView`/`SparklineMenuItemView`) — built the same way and for
/// the same reason: pure AppKit, no SwiftUI hosting, so the menu stays native
/// and leak-free. Decorative: it does not intercept clicks, so the row's normal
/// action still fires, including the richer Liquid Glass chart popover a chart
/// row opts into (`AppActionDispatcher` reads `params.swiftbar.chart`
/// independently of whichever view the row renders).
final class CategoryChartMenuItemView: NSView {
    /// Surface gap between adjacent segments, in points. Two abutting fills with
    /// no gap read as one shape at menu-row scale; the gap is what makes the
    /// segment boundary legible — and it is also the secondary encoding that
    /// keeps neighbouring hues distinguishable without relying on color alone.
    private static let segmentGap: CGFloat = 2
    /// Donut hole, as a share of the outer radius.
    private static let donutInnerRatio: CGFloat = 0.58

    private let title: NSAttributedString
    private let chart: ChartParams
    private let colors: [NSColor]
    private let layout: ProgressBarLayout

    init(title: NSAttributedString, chart: ChartParams, leading: Bool = false) {
        self.title = title
        self.chart = chart
        self.colors = chart.values.indices.map { ChartColorResolver.nsColor(for: chart, at: $0) }

        // Circular shapes get a square slot; the stacked bar reuses the same
        // capsule geometry `progress=` uses, so the two line up when a menu
        // mixes them.
        // Named explicitly rather than via `Self`, which is not available
        // before `super.init` in a class initializer.
        let size = CategoryChartMenuItemView.accessorySize(for: chart)
        let layout = ProgressBarLayout(barWidth: size.width, barHeight: size.height, leading: leading)
        self.layout = layout

        let rowHeight = Swift.max(22, size.height + 10)
        // Size to fit label + chart so the menu grows wide enough, matching
        // ProgressMenuItemView/SparklineMenuItemView's sizing. A `chartw=full`
        // chart claims no width of its own here on purpose: it stretches to
        // whatever width the menu ends up with, so it must not be the row that
        // decides that width.
        let titleWidth = title.size().width.rounded(.up)
        let claimedWidth = chart.isFullWidth ? 0 : size.width
        let desiredWidth = layout.leadingInset + titleWidth + layout.gap + claimedWidth + layout.trailingInset
        super.init(frame: NSRect(x: 0, y: 0, width: Swift.max(240, desiredWidth), height: rowHeight))
        autoresizingMask = [.width]

        // VoiceOver: a custom `NSMenuItem.view` draws its own title and is
        // otherwise silent, and a share chart is exactly the case where the data
        // must not be conveyed by color alone — so read out every segment's
        // label and percentage.
        setAccessibilityElement(true)
        setAccessibilityLabel(title.string)
        setAccessibilityValue(chart.accessibilitySummary())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The accessory slot `chart` occupies, in points: its `chartw=`/`charth=`
    /// if it declared any, otherwise the per-kind default. Both come from
    /// `ChartParams` so the SwiftUI row (`MenuRowAccessory`) measures the same
    /// chart identically. Exposed for the layout tests, which assert the
    /// geometry without rendering.
    static func accessorySize(for chart: ChartParams) -> CGSize {
        let size = chart.inlineSize
        return CGSize(width: size.width, height: size.height)
    }

    /// Width a `chartw=full` chart takes: the row's content width, less its own
    /// text when it has any. Computed at draw time rather than at init, because
    /// the row is only as wide as the menu — which the *widest* row decides,
    /// and that may be some other row entirely.
    ///
    /// Static and geometry-only so the stretch is unit-testable without a live
    /// menu, like `sectorPath`.
    static func stretchedWidth(layout: ProgressBarLayout, title: NSAttributedString, in bounds: CGRect) -> CGFloat {
        let titleWidth = title.size().width.rounded(.up)
        let reserved = titleWidth > 0 ? titleWidth + layout.gap : 0
        let available = bounds.width - layout.leadingInset - layout.trailingInset - reserved
        // Never collapse to nothing in a too-narrow menu: fall back to the
        // declared/default slot, which is what a non-full chart would have taken.
        return Swift.max(available, layout.barWidth)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let highlight = menuRowHighlightPath(highlighted: enclosingMenuItem?.isHighlighted ?? false, in: bounds) {
            NSColor.selectedContentBackgroundColor.setFill()
            highlight.fill()
        }

        // `fraction` drives progress='s fill rect only; a chart uses the track
        // rect as its whole drawing area and ignores it.
        var layout = self.layout
        if chart.isFullWidth { layout.barWidth = Self.stretchedWidth(layout: layout, title: title, in: bounds) }
        let rects = layout.rects(in: bounds, fraction: 0)
        title.drawTruncatedCentered(in: rects.label)

        switch chart.kind {
        case .pie: drawRadial(in: rects.track, innerRatio: 0)
        case .donut: drawRadial(in: rects.track, innerRatio: Self.donutInnerRatio)
        case .stackedBar: drawStackedBar(in: rects.track)
        }
    }

    // MARK: - Shapes

    /// Draws the series as a pie (`innerRatio == 0`) or a donut, starting at
    /// twelve o'clock and running clockwise — the direction a reader expects a
    /// share chart to advance.
    private func drawRadial(in rect: CGRect, innerRatio: CGFloat) {
        let outer = Swift.min(rect.width, rect.height) / 2
        guard outer > 0 else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = outer * innerRatio

        // The angular equivalent of `segmentGap` at the outer edge. A lone
        // segment is a whole circle with no neighbour to separate from, so it
        // takes no padding — otherwise it would render with a spurious notch.
        let padDegrees = chart.values.count > 1
            ? (Self.segmentGap / 2 / outer) * 180 / .pi
            : 0

        var cumulative: CGFloat = 0
        for index in chart.values.indices {
            let sweep = CGFloat(chart.fraction(at: index)) * 360
            defer { cumulative += sweep }
            guard sweep > 0 else { continue }

            let start = 90 - cumulative
            let end = start - sweep
            // Never let the gap eat a slice: a sliver keeps its own hue visible
            // rather than vanishing into its neighbours' padding.
            let pad = Swift.min(padDegrees, sweep / 4)
            let path = Self.sectorPath(
                center: center, inner: inner, outer: outer,
                from: start - pad, to: end + pad
            )
            colors[index].setFill()
            path.fill()
        }
    }

    /// One pie/donut slice: an annular sector when `inner > 0`, a wedge from the
    /// center when it is 0. Static and geometry-only so it is unit-testable
    /// without a live menu.
    static func sectorPath(center: CGPoint, inner: CGFloat, outer: CGFloat, from start: CGFloat, to end: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        guard start > end else { return path }
        if inner > 0 {
            path.appendArc(withCenter: center, radius: inner, startAngle: start, endAngle: end, clockwise: true)
            path.appendArc(withCenter: center, radius: outer, startAngle: end, endAngle: start, clockwise: false)
        } else {
            path.move(to: center)
            path.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end, clockwise: true)
        }
        path.close()
        return path
    }

    /// Draws the series as one horizontal bar of end-to-end segments, clipped to
    /// the same capsule shape `progress=` uses so the two read as the same
    /// component — one filled by a single fraction, one by many.
    private func drawStackedBar(in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let radius = rect.height / 2
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

        let gap = chart.values.count > 1 ? Self.segmentGap : 0
        var cumulative: CGFloat = 0
        for index in chart.values.indices {
            let fraction = CGFloat(chart.fraction(at: index))
            defer { cumulative += fraction }
            guard fraction > 0 else { continue }

            let x = rect.minX + rect.width * cumulative
            let width = rect.width * fraction
            // Halve the gap on each interior edge so the space *between* two
            // segments is one `segmentGap`, and leave the outer ends flush with
            // the capsule.
            let leadingTrim = index == 0 ? 0 : gap / 2
            let trailingTrim = index == chart.values.count - 1 ? 0 : gap / 2
            let segment = CGRect(
                x: x + leadingTrim,
                y: rect.minY,
                width: width - leadingTrim - trailingTrim,
                height: rect.height
            )
            guard segment.width > 0 else { continue }
            colors[index].setFill()
            NSBezierPath(rect: segment).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
