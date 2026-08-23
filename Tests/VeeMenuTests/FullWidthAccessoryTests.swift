import AppKit
import XCTest
@testable import VeeMenu
import VeePluginFormat

/// `progressw=full` / `chartw=full` / `sparklinew=full` all mean the same
/// thing — take the row's leftover width — so they must resolve to the *same*
/// width for the same row. Geometry only, no rendering.
final class FullWidthAccessoryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 22)
    private let title = NSAttributedString(string: "Label")

    private func stretched(barWidth: CGFloat) -> CGFloat {
        let layout = ProgressBarLayout(barWidth: barWidth, barHeight: 6)
        return ProgressBarLayout.stretchedWidth(layout: layout, title: title, in: bounds)
    }

    /// The shared stretch is independent of the accessory's declared slot, so a
    /// gauge and a stacked bar in the same row reach the same width.
    func testTheStretchIsTheSameWhateverTheDeclaredSlot() {
        let gauge = stretched(barWidth: CGFloat(ProgressParams.defaultWidth))
        let bar = stretched(barWidth: CategoryChartMenuItemView.accessorySize(
            for: ChartParams(kind: .stackedBar, values: [30, 20, 50])
        ).width)
        XCTAssertEqual(gauge, bar, accuracy: 0.5)
    }

    func testAStretchedAccessoryIsWiderThanItsDefaultSlot() {
        XCTAssertGreaterThan(stretched(barWidth: CGFloat(ProgressParams.defaultWidth)), CGFloat(ProgressParams.defaultWidth))
    }

    /// A too-narrow row falls back to the declared slot rather than collapsing.
    func testANarrowRowFallsBackToTheDeclaredSlot() {
        let layout = ProgressBarLayout(barWidth: 120, barHeight: 6)
        let narrow = CGRect(x: 0, y: 0, width: 60, height: 22)
        XCTAssertEqual(ProgressBarLayout.stretchedWidth(layout: layout, title: title, in: narrow), 120)
    }

    // MARK: - The model keeps the flag

    func testAStackedBarKeepsChartWidthFull() {
        var params = LineParams()
        params.swiftbar.chart = ChartParams(kind: .stackedBar, values: [30, 20, 50], isFullWidth: true)
        guard case .chart(let chart) = MenuTree.accessory(for: params) else { return XCTFail("expected a chart") }
        XCTAssertTrue(chart.isFullWidth, "the flag must survive into the resolved row both surfaces read")
    }

    func testAStackedBarRowClaimsNoFixedWidthWhenFull() {
        let full = ChartParams(kind: .stackedBar, values: [30, 20, 50], isFullWidth: true)
        let fixed = ChartParams(kind: .stackedBar, values: [30, 20, 50])
        // Both report the same accessory slot; `isFullWidth` is what the row
        // consults to stop claiming it, so the flag — not the slot — is the
        // thing that has to travel.
        XCTAssertEqual(
            CategoryChartMenuItemView.accessorySize(for: full).width,
            CategoryChartMenuItemView.accessorySize(for: fixed).width
        )
        XCTAssertTrue(full.isFullWidth)
        XCTAssertFalse(fixed.isFullWidth)
    }
}
