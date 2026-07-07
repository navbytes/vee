import XCTest
@testable import VeeApp
import VeePluginFormat

/// Covers `PluginCoordinator.widgetFields`, which distills a parsed plugin
/// output into the presentation the WidgetKit snapshot carries (color, SF
/// Symbol, a headline gauge/sparkline).
final class WidgetFieldsTests: XCTestCase {
    private func fields(title: LineParams? = nil, ansiRuns: [AnsiRun] = [], body: [MenuNode] = []) -> WidgetTitleFields {
        let lines = title.map { [TitleLine(text: "x", params: $0, ansiRuns: ansiRuns)] } ?? []
        return PluginCoordinator.widgetFields(from: ParsedOutput(titleLines: lines, body: body))
    }

    func testEmptyOutputYieldsEmptyFields() {
        XCTAssertEqual(fields(), WidgetTitleFields())
    }

    func testTakesColorAndSymbolFromTitle() {
        var p = LineParams()
        p.color = .named("green")
        p.swiftbar.sfimage = "internaldrive"
        p.swiftbar.sfcolor = [.named("green"), .named("red")]
        let f = fields(title: p)
        XCTAssertEqual(f.color, .named("green"))
        XCTAssertEqual(f.symbolName, "internaldrive")
        XCTAssertEqual(f.symbolColors, [.named("green"), .named("red")])
    }

    func testFallsBackToFirstAnsiForegroundForColor() {
        let runs = [AnsiRun(range: 0..<1, foreground: .rgb(r: 1, g: 2, b: 3, a: 255))]
        XCTAssertEqual(fields(title: LineParams(), ansiRuns: runs).color, .rgb(r: 1, g: 2, b: 3, a: 255))
    }

    func testTakesProgressFromTitle() {
        var p = LineParams()
        p.progress = ProgressParams(fraction: 0.42)
        XCTAssertEqual(fields(title: p).progress, 0.42)
    }

    func testFallsBackToFirstBodyItemForProgressAndSparkline() {
        var bp = LineParams()
        bp.progress = ProgressParams(fraction: 0.9)
        bp.sparkline = [3, 2, 1]
        let body: [MenuNode] = [.separator, .item(MenuItem(text: "detail", params: bp))]
        let f = fields(title: LineParams(), body: body)
        XCTAssertEqual(f.progress, 0.9)
        XCTAssertEqual(f.sparkline, [3, 2, 1])
    }

    func testTitleProgressWinsOverBody() {
        var tp = LineParams()
        tp.progress = ProgressParams(fraction: 0.1)
        var bp = LineParams()
        bp.progress = ProgressParams(fraction: 0.9)
        let f = fields(title: tp, body: [.item(MenuItem(text: "d", params: bp))])
        XCTAssertEqual(f.progress, 0.1)
    }

    func testTakesSparklineFromTitle() {
        var p = LineParams()
        p.sparkline = [1, 2, 3, 4]
        XCTAssertEqual(fields(title: p).sparkline, [1, 2, 3, 4])
    }
}
