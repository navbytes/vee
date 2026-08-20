import Charts
import SwiftUI
import VeePluginFormat

/// Renders a plugin's inline `sparkline=…` series as a compact Swift Charts
/// line/area chart on a Liquid Glass surface — rich UI rendered natively, with
/// no WebView. Styling reuses the app's established card idiom (a continuous
/// rounded rectangle) over a translucent material for the macOS 26 Liquid Glass
/// look, and tints the series with the app's `accentColor` (see `DesignKit`).
public struct SparklineChartView: View {
    private let values: [Double]
    private let title: String

    public init(values: [Double], title: String = "") {
        self.values = values
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.headline).lineLimit(1)
            }
            chart
            footer
        }
        .padding(14)
        .frame(minWidth: 220, minHeight: 120)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Corner.popover, style: .continuous))
    }

    @ViewBuilder
    private var chart: some View {
        if points.count >= 2 {
            Chart(points) { point in
                AreaMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 64)
        } else {
            Text("Not enough data to chart.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 64)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let last = values.last {
            HStack {
                Text(Self.format(last))
                    .font(.title3).fontWeight(.semibold).monospacedDigit()
                Spacer()
                if let range = rangeLabel {
                    Text(range)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private var points: [Point] {
        values.enumerated().map { Point(index: $0.offset, value: $0.element) }
    }

    private var rangeLabel: String? {
        guard let min = values.min(), let max = values.max() else { return nil }
        return "\(Self.format(min))–\(Self.format(max))"
    }

    private static func format(_ v: Double) -> String {
        CompactNumber.label(v)
    }

    private struct Point: Identifiable {
        let index: Int
        let value: Double
        var id: Int { index }
    }
}
