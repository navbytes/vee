import Charts
import SwiftUI
import VeePluginFormat

/// The compact rich graphic a menu row carries in a detached window: a
/// `progress=` gauge, a `sparkline=`, a `pie=`/`donut=`/`stackedbar=` chart, or
/// a live `toggle=`/`slider=` control.
///
/// Deliberately *not* the popover views (`SparklineChartView`,
/// `CategoryChartView`, `PluginControlView`). Those are full-size surfaces that
/// bake in their own Liquid Glass card, 14pt padding, and a 220pt minimum
/// width — a card inside a list row, several times the height of the row it sits
/// in. The menu bar already draws this distinction, with `SparklineMenuItemView`
/// / `CategoryChartMenuItemView` inline in a row and the popover views on click;
/// this is the SwiftUI counterpart of the inline half, and clicking a row still
/// opens the popover exactly as it does from the menu.
///
/// Nothing here re-decides anything the other renderers already decide. Segment
/// colors come from `ChartSegmentColor`, the donut ratio and segment gap from
/// `CategoryChartView`, and gauge dimensions from `ProgressParams` (which the
/// AppKit menu row reads too), so a chart drawn here and the same chart drawn in
/// the popover or the menu agree by construction.
public struct MenuRowAccessory: View {
    /// Which graphic a row carries, if any.
    public enum Kind: Equatable, Sendable {
        case control(PluginControl)
        case progress(ProgressParams, tint: VeeColor?)
        case sparkline([Double], tint: VeeColor?)
        case chart(ChartParams)
    }

    private let kind: Kind
    private let leading: Bool
    private let onCommit: @MainActor (Double) -> Void

    public init(kind: Kind, leading: Bool = false, onCommit: @escaping @MainActor (Double) -> Void = { _ in }) {
        self.kind = kind
        self.leading = leading
        self.onCommit = onCommit
    }

    /// The graphic `params` declares, or `nil` for a plain row.
    ///
    /// Precedence follows `AppActionDispatcher`'s dispatch order — control
    /// first, then the display-only graphics in the order `MenuBuilder` draws
    /// them inline (progress, sparkline, chart). A row declaring several shows
    /// the one that would act on click, so the graphic never advertises a
    /// different surface than the row opens.
    ///
    /// Pure, so the precedence is unit-testable without rendering.
    public static func kind(for params: LineParams) -> Kind? {
        if let control = params.control { return .control(control) }
        if let progress = params.progress { return .progress(progress, tint: params.color) }
        if let series = params.sparkline, !series.isEmpty { return .sparkline(series, tint: params.color) }
        if let chart = params.swiftbar.chart { return .chart(chart) }
        return nil
    }

    public var body: some View {
        switch kind {
        case .control(let control):
            InlineControl(control: control, onCommit: onCommit)
        case .progress(let progress, let tint):
            gauge(progress, tint: tint)
        case .sparkline(let values, let tint):
            sparkline(values, tint: tint)
        case .chart(let chart):
            CompactChart(chart: chart)
        }
    }

    // MARK: - Progress

    /// `progress=` as a capsule, at the same dimensions the menu row draws it:
    /// `progressw=`/`progressh=` when declared, otherwise `ProgressBarLayout`'s
    /// defaults, which `MenuBuilder` reads from the same place.
    private func gauge(_ progress: ProgressParams, tint: VeeColor?) -> some View {
        let width = CGFloat(progress.effectiveWidth)
        let height = CGFloat(progress.effectiveHeight)
        let fill = tint.flatMap(SwiftUIColor.resolve) ?? .accentColor
        let track = progress.trackColor.flatMap(SwiftUIColor.resolve)
            ?? Color(nsColor: .tertiaryLabelColor).opacity(0.25)
        return ZStack(alignment: .leading) {
            Capsule().fill(track)
            Capsule().fill(fill)
                .frame(width: width * CGFloat(min(max(progress.fraction, 0), 1)))
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress.fraction * 100).rounded())) percent")
    }

    // MARK: - Sparkline

    /// A bare trend line — no axes, no footer, no card. The popover
    /// (`SparklineChartView`) is where the value and range labels live, and a
    /// click still opens it.
    @ViewBuilder
    private func sparkline(_ values: [Double], tint: VeeColor?) -> some View {
        let color = tint.flatMap(SwiftUIColor.resolve) ?? .accentColor
        if values.count >= 2 {
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Index", index), y: .value("Value", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { $0.background(.clear) }
            .frame(width: Self.sparklineWidth, height: Self.accessoryHeight)
            .accessibilityElement()
            .accessibilityLabel("Sparkline")
            .accessibilityValue(Self.sparklineSummary(values))
        } else {
            // One point (or none) is not a trend. Hold the slot so rows stay
            // aligned rather than jumping when a series grows to two.
            Color.clear.frame(width: Self.sparklineWidth, height: Self.accessoryHeight)
        }
    }

    static func sparklineSummary(_ values: [Double]) -> String {
        guard let last = values.last, let low = values.min(), let high = values.max() else { return "no data" }
        return "latest \(CompactNumber.label(last)), range \(CompactNumber.label(low)) to \(CompactNumber.label(high))"
    }

    static let sparklineWidth: CGFloat = 64
    static let accessoryHeight: CGFloat = 18
}

// MARK: - Chart

/// A row-sized `pie=`/`donut=`/`stackedbar=`, drawn with the same shapes,
/// ratios, and colors as the popover — just small, and without the legend
/// (which is what the popover exists to show).
private struct CompactChart: View {
    let chart: ChartParams

    var body: some View {
        Group {
            switch chart.kind {
            case .pie: radial(innerRadius: 0)
            case .donut: radial(innerRadius: CategoryChartView.donutInnerRatio)
            case .stackedBar: stackedBar
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chart")
        .accessibilityValue(chart.accessibilitySummary())
    }

    private func radial(innerRadius: Double) -> some View {
        Chart(Array(chart.values.enumerated()), id: \.offset) { index, value in
            SectorMark(
                angle: .value("Share", value),
                innerRadius: .ratio(innerRadius),
                angularInset: CategoryChartView.segmentGap / 2
            )
            .foregroundStyle(ChartSegmentColor.color(for: chart, at: index))
        }
        .chartLegend(.hidden)
        .frame(width: MenuRowAccessory.accessoryHeight, height: MenuRowAccessory.accessoryHeight)
    }

    private var stackedBar: some View {
        GeometryReader { geometry in
            let gaps = CategoryChartView.segmentGap * Double(max(0, chart.values.count - 1))
            let usable = max(0, Double(geometry.size.width) - gaps)
            HStack(spacing: CategoryChartView.segmentGap) {
                ForEach(Array(chart.values.indices), id: \.self) { index in
                    ChartSegmentColor.color(for: chart, at: index)
                        .frame(width: usable * chart.fraction(at: index))
                }
            }
            .frame(height: geometry.size.height, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(width: MenuRowAccessory.sparklineWidth, height: 8)
    }
}

// MARK: - Control

/// A live `toggle=`/`slider=` sized for a row.
///
/// Unlike the popover's `PluginControlView`, this one **adopts values arriving
/// from later refreshes**: a detached window can be open across hundreds of
/// refreshes, and a switch that kept showing the state it had when the window
/// opened would be exactly the stale-looking-live reading the whole design
/// refuses. Adoption is suppressed mid-drag so a refresh can't yank the knob out
/// from under the pointer.
private struct InlineControl: View {
    let control: PluginControl
    let onCommit: @MainActor (Double) -> Void

    @State private var value: Double
    @State private var isEditing = false

    init(control: PluginControl, onCommit: @escaping @MainActor (Double) -> Void) {
        self.control = control
        self.onCommit = onCommit
        _value = State(initialValue: Self.value(of: control))
    }

    var body: some View {
        content
            .onChange(of: Self.value(of: control)) { _, declared in
                guard !isEditing else { return }
                value = declared
            }
    }

    @ViewBuilder
    private var content: some View {
        switch control {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { value != 0 },
                set: { value = $0 ? 1 : 0; onCommit(value) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(.accentColor)
            .accessibilityLabel("Toggle")

        case .slider(let min, let max, _):
            HStack(spacing: 6) {
                Slider(value: $value, in: min...max, onEditingChanged: { editing in
                    isEditing = editing
                    if !editing { onCommit(value) }   // commit once, when the drag settles
                })
                .controlSize(.mini)
                .tint(.accentColor)
                .frame(width: MenuRowAccessory.sparklineWidth)
                Text(CompactNumber.label(value))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Slider")
        }
    }

    private static func value(of control: PluginControl) -> Double {
        switch control {
        case .toggle(let on): return on ? 1 : 0
        case .slider(_, _, let value): return value
        }
    }
}
