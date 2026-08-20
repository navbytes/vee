import XCTest
import VeePluginFormat
import VeeUI
@testable import VeeApp

/// Covers the pure decisions behind detached popover windows: which rows can be
/// torn off, and which surface a row carrying several accessories detaches as.
/// Window lifetime itself needs a real `NSWindow` and is left to manual checking
/// rather than opening windows in the test process.
@MainActor
final class DetachedPopoverWindowsTests: XCTestCase {
    private func item(
        sparkline: [Double]? = nil,
        chart: ChartParams? = nil,
        control: PluginControl? = nil,
        progress: Double? = nil
    ) -> MenuItem {
        var p = LineParams()
        p.sparkline = sparkline
        p.swiftbar.chart = chart
        p.control = control
        if let progress { p.progress = ProgressParams(fraction: progress) }
        return MenuItem(text: "row", params: p)
    }

    /// Every popover kind is detachable — controls included, which is the whole
    /// point of the button being universal rather than chart-only.
    func testEveryPopoverKindIsDetachable() {
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(item(sparkline: [1, 2, 3])))
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(item(chart: ChartParams(kind: .pie, values: [1, 2]))))
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(item(control: .toggle(on: true))))
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(item(control: .slider(min: 0, max: 10, value: 3))))
    }

    /// The button must not appear on rows that open no popover at all —
    /// including `progress=`, which is an in-row gauge and never opens one.
    func testRowsWithoutAPopoverAreNotDetachable() {
        XCTAssertFalse(DetachedPopoverWindows.isDetachable(item()))
        XCTAssertFalse(DetachedPopoverWindows.isDetachable(item(progress: 0.5)))
        XCTAssertFalse(DetachedPopoverWindows.isDetachable(item(sparkline: [])))
    }

    /// A row carrying several accessories opens exactly one popover, and the
    /// dispatcher decides which: control first, then sparkline, then chart.
    /// Detaching must reproduce that same surface — the button must never swap
    /// one out from under the user.
    func testRowsWithSeveralAccessoriesAreStillDetachable() {
        let all = item(
            sparkline: [1, 2, 3],
            chart: ChartParams(kind: .donut, values: [1, 1]),
            control: .toggle(on: false)
        )
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(all))
        XCTAssertTrue(DetachedPopoverWindows.isDetachable(
            item(sparkline: [1, 2, 3], chart: ChartParams(kind: .donut, values: [1, 1]))
        ))
    }

    // MARK: - Window title

    func testWindowTitleCombinesRowAndPlugin() {
        XCTAssertEqual(DetachedPopoverWindows.windowTitle(row: "Load", plugin: "cpu"), "Load — cpu")
    }

    /// Row text is plugin-supplied and can carry the newlines the format's `\n`
    /// escape produces; a title bar renders those as stray glyphs.
    func testWindowTitleFlattensNewlinesAndTrims() {
        XCTAssertEqual(DetachedPopoverWindows.windowTitle(row: "Load\naverage", plugin: "cpu"), "Load average — cpu")
        XCTAssertEqual(DetachedPopoverWindows.windowTitle(row: "  Load  ", plugin: "cpu"), "Load — cpu")
    }

    func testWindowTitleFallsBackToThePluginForAnEmptyRow() {
        XCTAssertEqual(DetachedPopoverWindows.windowTitle(row: "", plugin: "cpu"), "cpu")
        XCTAssertEqual(DetachedPopoverWindows.windowTitle(row: "   ", plugin: "cpu"), "cpu")
    }

    func testWindowTitleClipsARunawayRow() {
        let title = DetachedPopoverWindows.windowTitle(row: String(repeating: "x", count: 200), plugin: "cpu")
        XCTAssertTrue(title.hasSuffix("… — cpu"), title)
        XCTAssertLessThan(title.count, 80)
    }
}

/// The live-update contract of one detached window's model.
@MainActor
final class DetachedPopoverModelTests: XCTestCase {
    func testUpdateReplacesContentAndClearsStale() {
        let model = DetachedPopoverModel(pluginName: "cpu", title: "Load", content: .sparkline([1, 2]))
        model.markStale()
        XCTAssertTrue(model.isStale)

        model.update(title: "Load 40%", content: .sparkline([3, 4]))
        XCTAssertEqual(model.title, "Load 40%")
        XCTAssertEqual(model.content, .sparkline([3, 4]))
        XCTAssertFalse(model.isStale, "fresh data must clear the stale flag")
    }

    /// A detached control routes its committed value back out through the model,
    /// which is what lets a torn-off `toggle=`/`slider=` still drive the plugin.
    func testCommitForwardsTheValue() {
        // A reference type rather than a captured local `var`: the model stores
        // the closure, so the capture escapes the test body.
        let recorder = Recorder()
        let model = DetachedPopoverModel(
            pluginName: "wifi",
            title: "Wi-Fi",
            content: .control(.slider(min: 0, max: 100, value: 40))
        ) { recorder.values.append($0) }

        model.commit(72)
        model.commit(10)
        XCTAssertEqual(recorder.values, [72, 10])
    }

    @MainActor
    private final class Recorder {
        var values: [Double] = []
    }

    /// A read-only window has no commit path; calling it must be inert rather
    /// than a crash, since the view calls through the same model API.
    func testCommitOnAReadOnlyWindowIsInert() {
        let model = DetachedPopoverModel(pluginName: "cpu", title: "Load", content: .sparkline([1, 2]))
        model.commit(5)
    }

    /// A vanished row keeps its last value on screen — blanking would lose the
    /// reading the user was watching — but stops claiming to be current.
    func testMarkStaleKeepsTheLastContent() {
        let chart = ChartParams(kind: .pie, values: [45, 30, 25])
        let model = DetachedPopoverModel(pluginName: "disk", title: "By category", content: .chart(chart))
        model.markStale()
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.content, .chart(chart))
        XCTAssertEqual(model.title, "By category")
    }
}
