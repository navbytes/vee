import XCTest
import SwiftUI
import AppKit
@testable import VeeUI
@testable import VeePluginFormat

@MainActor
/// The popover host (`PluginPopover`) opens a fixed-size window sized from
/// `CategoryChartView.cardHeight`. If the card ever renders taller than that
/// number claims, the chart is silently clipped on screen — so measure the real
/// rendered card and hold the number to it.
final class CategoryChartCardSizeTests: XCTestCase {
    func testCardHeightCoversRenderedCard() throws {
        for line in ["x | donut=512,256,128 chartlabels=A,B,C", "x | pie=1,2,3,4", "x | stackedbar=60,25,15"] {
            let (_, pairs, _) = LineParser.splitTextAndParams(line)
            let chart = LineParser.mapParams(pairs).params.swiftbar.chart!
            let renderer = ImageRenderer(content: CategoryChartView(chart: chart, title: "Volumes"))
            let actual = try XCTUnwrap(renderer.nsImage).size.height
            let declared = CategoryChartView.cardHeight(for: chart, hasTitle: true)
            XCTAssertGreaterThanOrEqual(declared, actual, "popover would clip \(chart.kind)")
        }
    }
}
