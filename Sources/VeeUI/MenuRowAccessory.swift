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
        /// A live `toggle=`/`slider=`, drawn in place because a window *can*
        /// host one. The menu bar cannot, and draws the display graphic
        /// instead — the one difference between the two surfaces, and a
        /// property of the presentation rather than of the row.
        ///
        /// `width` is `accessoryw=`, or `nil` for the default track width.
        case control(PluginControl, width: Double?)
        /// The row's display graphic, selected by the shared rule in
        /// `MenuTree.accessory` so this surface and the dropdown can never
        /// disagree about which one a row carries.
        case display(MenuAccessory)
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
    /// A live control wins, because this surface can host one and the row's
    /// click acts on it. Everything else defers to `MenuTree.accessory` — the
    /// single definition of display-graphic precedence, shared with the AppKit
    /// dropdown, which this method used to duplicate.
    ///
    /// Pure, so the precedence is unit-testable without rendering.
    public static func kind(for params: LineParams) -> Kind? {
        if let control = params.control { return .control(control, width: params.controlWidth) }
        return MenuTree.accessory(for: params).map(Kind.display)
    }

    public var body: some View {
        switch kind {
        case .control(let control, let width):
            InlineControl(control: control, width: width, onCommit: onCommit)
        case .display(.progress(let progress, let tint)):
            gauge(progress, tint: tint)
        case .display(.sparkline(let values, let style, let tint)):
            sparkline(values, style: style, tint: tint)
        case .display(.chart(let chart)):
            CompactChart(chart: chart)
        }
    }

    // MARK: - Progress

    /// `progress=` as a capsule, at the same dimensions the menu row draws it:
    /// `progressw=`/`progressh=` when declared, otherwise `ProgressBarLayout`'s
    /// defaults, which `MenuBuilder` reads from the same place.
    @ViewBuilder
    private func gauge(_ progress: ProgressParams, tint: VeeColor?) -> some View {
        let bar = capsule(progress, tint: tint)
            .frame(height: CGFloat(progress.effectiveHeight))
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((progress.fraction * 100).rounded())) percent")
        // `progressw=full`: take the row's leftover width, exactly as the menu
        // row does — the same knob a `chartw=full` stacked bar uses below.
        if progress.isFullWidth { bar.frame(maxWidth: .infinity) } else { bar.frame(width: CGFloat(progress.effectiveWidth)) }
    }

    /// The track and its fill. `GeometryReader` rather than a fraction of the
    /// declared width, so a stretched bar fills the width it actually got.
    private func capsule(_ progress: ProgressParams, tint: VeeColor?) -> some View {
        let fill = tint.flatMap(SwiftUIColor.resolve) ?? .accentColor
        let track = progress.trackColor.flatMap(SwiftUIColor.resolve)
            ?? Color(nsColor: .tertiaryLabelColor).opacity(0.25)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: geometry.size.width * CGFloat(min(max(progress.fraction, 0), 1)))
            }
        }
    }

    // MARK: - Sparkline

    /// A bare trend line — no axes, no footer, no card. The popover
    /// (`SparklineChartView`) is where the value and range labels live, and a
    /// click still opens it.
    ///
    /// Colour and dimensions come from `SparklineStyle`, the same values the
    /// AppKit menu row reads: `sparklinecolor=` wins, then the row's `color=`,
    /// then the accent; `sparklinew=`/`sparklineh=` set the size, defaulting to
    /// `SparklineStyle`'s. This row used to hardcode 64×20 and ignore all three
    /// params, so the same series drew at a different size and colour here than
    /// in the dropdown.
    @ViewBuilder
    private func sparkline(_ values: [Double], style: SparklineStyle, tint: VeeColor?) -> some View {
        let color = style.color.flatMap(SwiftUIColor.resolve)
            ?? tint.flatMap(SwiftUIColor.resolve)
            ?? .accentColor
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
            .modifier(SparklineFrame(style: style))
            .accessibilityElement()
            .accessibilityLabel("Sparkline")
            .accessibilityValue(Self.sparklineSummary(values))
        } else {
            // One point (or none) is not a trend. Hold the slot so rows stay
            // aligned rather than jumping when a series grows to two.
            Color.clear.modifier(SparklineFrame(style: style))
        }
    }

    static func sparklineSummary(_ values: [Double]) -> String {
        guard let last = values.last, let low = values.min(), let high = values.max() else { return "no data" }
        return "latest \(CompactNumber.label(last)), range \(CompactNumber.label(low)) to \(CompactNumber.label(high))"
    }

    static let accessoryHeight: CGFloat = 18

    /// Track width for an inline `slider=` that declares no `accessoryw=`.
    /// Its own constant rather than the sparkline's: the two happened to share
    /// a number, not a reason.
    static let defaultSliderWidth: CGFloat = 64
}

/// Sizes a sparkline from its `SparklineStyle`, honouring `sparklinew=full` the
/// same way `progressw=full` and `chartw=full` are honoured above: stretch to
/// the row's leftover width instead of a fixed number of points.
private struct SparklineFrame: ViewModifier {
    let style: SparklineStyle

    func body(content: Content) -> some View {
        if style.isFullWidth {
            content.frame(maxWidth: .infinity).frame(height: CGFloat(style.effectiveHeight))
        } else {
            content.frame(width: CGFloat(style.effectiveWidth), height: CGFloat(style.effectiveHeight))
        }
    }
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
        .frame(width: chart.inlineSize.width, height: chart.inlineSize.height)
    }

    @ViewBuilder
    private var stackedBar: some View {
        if chart.isFullWidth { bar.frame(maxWidth: .infinity) } else { bar.frame(width: chart.inlineSize.width) }
    }

    private var bar: some View {
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
        .frame(height: chart.inlineSize.height)
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
    /// `accessoryw=`, or `nil` for the default track width. A toggle ignores
    /// it: a switch is a fixed system control with no width to give it.
    let width: Double?
    let onCommit: @MainActor (Double) -> Void

    @State private var value: Double
    @State private var isEditing = false

    init(control: PluginControl, width: Double? = nil, onCommit: @escaping @MainActor (Double) -> Void) {
        self.control = control
        self.width = width
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
                .frame(width: width.map { CGFloat($0) } ?? MenuRowAccessory.defaultSliderWidth)
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
