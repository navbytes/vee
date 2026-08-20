import XCTest
import VeePluginFormat
import VeeUI
@testable import VeeApp

/// Covers the pure decisions behind detached chart windows: which rows can be
/// torn off, and which surface a row that carries several accessories detaches
/// as. Window lifetime itself needs a real `NSWindow` and is left to manual
/// checking rather than opening windows in the test process.
@MainActor
final class DetachedChartWindowsTests: XCTestCase {
    private func item(sparkline: [Double]? = nil, chart: ChartParams? = nil, progress: Double? = nil) -> MenuItem {
        var p = LineParams()
        p.sparkline = sparkline
        p.swiftbar.chart = chart
        if let progress { p.progress = ProgressParams(fraction: progress) }
        return MenuItem(text: "row", params: p)
    }

    func testChartAndSparklineRowsAreDetachable() {
        XCTAssertTrue(DetachedChartWindows.isDetachable(item(sparkline: [1, 2, 3])))
        XCTAssertTrue(DetachedChartWindows.isDetachable(item(chart: ChartParams(kind: .pie, values: [1, 2]))))
    }

    /// The button must not appear on rows a window could show nothing for —
    /// including `progress=`, which is an in-row gauge with no popover at all.
    func testOtherRowsAreNotDetachable() {
        XCTAssertFalse(DetachedChartWindows.isDetachable(item()))
        XCTAssertFalse(DetachedChartWindows.isDetachable(item(progress: 0.5)))
        XCTAssertFalse(DetachedChartWindows.isDetachable(item(sparkline: [])))
    }

    /// A row carrying both opens the sparkline popover (the dispatcher checks it
    /// first), so detaching it must produce the same surface — otherwise the
    /// button would swap the chart out from under the user.
    func testSparklineWinsOverChartJustLikeTheDispatcher() {
        let both = item(sparkline: [1, 2, 3], chart: ChartParams(kind: .donut, values: [1, 1]))
        XCTAssertTrue(DetachedChartWindows.isDetachable(both))
    }

    // MARK: - Window title

    func testWindowTitleCombinesRowAndPlugin() {
        XCTAssertEqual(DetachedChartWindows.windowTitle(row: "Load", plugin: "cpu"), "Load — cpu")
    }

    /// Row text is plugin-supplied and can carry the newlines the format's `\n`
    /// escape produces; a title bar renders those as stray glyphs.
    func testWindowTitleFlattensNewlinesAndTrims() {
        XCTAssertEqual(DetachedChartWindows.windowTitle(row: "Load\naverage", plugin: "cpu"), "Load average — cpu")
        XCTAssertEqual(DetachedChartWindows.windowTitle(row: "  Load  ", plugin: "cpu"), "Load — cpu")
    }

    func testWindowTitleFallsBackToThePluginForAnEmptyRow() {
        XCTAssertEqual(DetachedChartWindows.windowTitle(row: "", plugin: "cpu"), "cpu")
        XCTAssertEqual(DetachedChartWindows.windowTitle(row: "   ", plugin: "cpu"), "cpu")
    }

    func testWindowTitleClipsARunawayRow() {
        let title = DetachedChartWindows.windowTitle(row: String(repeating: "x", count: 200), plugin: "cpu")
        XCTAssertTrue(title.hasSuffix("… — cpu"), title)
        XCTAssertLessThan(title.count, 80)
    }
}

/// The live-update contract of one detached window's model.
@MainActor
final class DetachedChartModelTests: XCTestCase {
    func testUpdateReplacesContentAndClearsStale() {
        let model = DetachedChartModel(pluginName: "cpu", title: "Load", content: .sparkline([1, 2]))
        model.markStale()
        XCTAssertTrue(model.isStale)

        model.update(title: "Load 40%", content: .sparkline([3, 4]))
        XCTAssertEqual(model.title, "Load 40%")
        XCTAssertEqual(model.content, .sparkline([3, 4]))
        XCTAssertFalse(model.isStale, "fresh data must clear the stale flag")
    }

    /// A vanished row keeps its last value on screen — blanking would lose the
    /// reading the user was watching — but stops claiming to be current.
    func testMarkStaleKeepsTheLastContent() {
        let chart = ChartParams(kind: .pie, values: [45, 30, 25])
        let model = DetachedChartModel(pluginName: "disk", title: "By category", content: .chart(chart))
        model.markStale()
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.content, .chart(chart))
        XCTAssertEqual(model.title, "By category")
    }
}
