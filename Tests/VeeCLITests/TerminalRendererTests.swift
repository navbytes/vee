import XCTest
import VeePluginFormat
@testable import VeeCLI

/// Covers the pure terminal renderer that powers `vee show`. Most assertions run
/// with color OFF so the output is plain and deterministic; a few check that
/// color ON emits the expected SGR escapes.
final class TerminalRendererTests: XCTestCase {
    private let plain = TerminalRenderer.Options(color: false, width: 80)

    // MARK: - Structure

    func testRendersTitleRuleAndNestedTree() {
        let details = MenuItem(text: "Details", submenu: [
            .item(MenuItem(text: "Load: 1.20")),
            .item(MenuItem(text: "Cores: 8"))
        ])
        var link = LineParams(); link.href = URL(string: "https://example.com")

        let output = ParsedOutput(
            titleLines: [TitleLine(text: "CPU 12%")],
            body: [
                .item(MenuItem(text: "Top processes", params: link)),
                .separator,
                .item(details)
            ])

        let rendered = TerminalRenderer.render(output, options: plain)
        XCTAssertTrue(rendered.contains("CPU 12%"), rendered)
        XCTAssertTrue(rendered.contains("Top processes"), rendered)
        XCTAssertTrue(rendered.contains("↗"), rendered)              // href action glyph
        XCTAssertTrue(rendered.contains("  Load: 1.20"), rendered)   // nested one level (2-space indent)
        XCTAssertTrue(rendered.contains("─"), rendered)              // title rule + separator
    }

    // MARK: - Rich params

    func testProgressBarIsDeterministicBlockGauge() {
        // 0.5 over 12 cells → 6 full blocks, 6 track cells, "50%".
        XCTAssertEqual(TerminalRenderer.progressBar(0.5, color: nil, options: plain), "██████░░░░░░ 50%")
        // Clamps out-of-range fractions.
        XCTAssertEqual(TerminalRenderer.progressBar(1.5, color: nil, options: plain), "████████████ 100%")
        XCTAssertEqual(TerminalRenderer.progressBar(-1, color: nil, options: plain), "░░░░░░░░░░░░ 0%")
    }

    func testSparklineNormalizesOverSeriesRange() {
        let s = TerminalRenderer.sparkline([1, 2, 3, 4, 5, 6, 7, 8], color: nil, options: plain)
        XCTAssertEqual(s, "▁▂▃▄▅▆▇█")
        // A flat series renders at mid height (no divide-by-zero).
        XCTAssertEqual(TerminalRenderer.sparkline([5, 5, 5], color: nil, options: plain), "▅▅▅")
    }

    func testCategoryChartIsAnExactlyWideSegmentedBar() {
        // 12 cells, split 50/25/25 → 6/3/3. The bar is always exactly as wide
        // as the progress gauge so mixed accessories line up in a column.
        let chart = ChartParams(kind: .pie, values: [50, 25, 25])
        XCTAssertEqual(TerminalRenderer.categoryChart(chart, options: plain), String(repeating: "█", count: 12))
    }

    func testChartCellAllocationSumsExactlyAndKeepsSliversVisible() {
        let even = ChartParams(kind: .pie, values: [1, 1, 1])
        XCTAssertEqual(TerminalRenderer.allocateCells(even, total: 12), [4, 4, 4])

        // Largest remainder: 1/3 of 10 cells can't split evenly.
        let uneven = ChartParams(kind: .pie, values: [1, 1, 1])
        XCTAssertEqual(TerminalRenderer.allocateCells(uneven, total: 10).reduce(0, +), 10)

        // A slice far below one cell still gets one, borrowed from the widest —
        // rounding it away would drop the segment from the chart entirely.
        let sliver = ChartParams(kind: .pie, values: [1000, 1, 1])
        let cells = TerminalRenderer.allocateCells(sliver, total: 12)
        XCTAssertEqual(cells.reduce(0, +), 12)
        XCTAssertTrue(cells.allSatisfy { $0 >= 1 })

        // A genuinely zero segment gets nothing — it has no share to show.
        XCTAssertEqual(TerminalRenderer.allocateCells(ChartParams(kind: .pie, values: [0, 1]), total: 4), [0, 4])
    }

    /// Regression: `VeeColor.parse` accepts any bare word as a name, so
    /// `chartcolors=notacolor` reaches the renderer intact and only fails when
    /// it is resolved to SGR codes. The AppKit and SwiftUI resolvers fall back
    /// to the segment's palette slot there; this one used to emit the segment
    /// uncoloured instead, so the same chart looked different in the terminal.
    func testChartFallsBackToThePaletteWhenAnOverrideCannotResolve() {
        let colored = TerminalRenderer.Options(color: true, width: 80)
        let chart = ChartParams(kind: .pie, values: [1, 1], colors: [.named("notacolor"), nil])
        let out = TerminalRenderer.categoryChart(chart, options: colored)
        // Slot 1's dark step (#3987e5) as truecolor SGR — what the unresolvable
        // override must fall back to.
        XCTAssertTrue(out.contains("38;2;57;135;229"), out)
    }

    /// A color the terminal *can* resolve still wins over the palette.
    func testResolvableOverrideBeatsThePalette() {
        let colored = TerminalRenderer.Options(color: true, width: 80)
        let chart = ChartParams(kind: .pie, values: [1, 1], colors: [.named("red"), nil])
        let out = TerminalRenderer.categoryChart(chart, options: colored)
        XCTAssertTrue(out.contains("\u{1B}[31m"), out)
    }

    func testChartRendersInlineOnTheRow() {
        var chart = LineParams()
        chart.swiftbar.chart = ChartParams(kind: .stackedBar, values: [1, 1])
        let r = TerminalRenderer.render(ParsedOutput(body: [.item(MenuItem(text: "Disk", params: chart))]), options: plain)
        XCTAssertTrue(r.contains("Disk"))
        XCTAssertTrue(r.contains("█"), "the chart should draw blocks on the row")
    }

    func testProgressSparklineAndControlsRenderInline() {
        var prog = LineParams(); prog.progress = ProgressParams(fraction: 0.5)
        var spark = LineParams(); spark.sparkline = [1, 4, 8]
        var on = LineParams(); on.control = .toggle(on: true)
        var off = LineParams(); off.control = .toggle(on: false)
        var slider = LineParams(); slider.control = .slider(min: 0, max: 10, value: 3)

        let output = ParsedOutput(body: [
            .item(MenuItem(text: "Sync", params: prog)),
            .item(MenuItem(text: "Load", params: spark)),
            .item(MenuItem(text: "Mute", params: on)),
            .item(MenuItem(text: "Wifi", params: off)),
            .item(MenuItem(text: "Vol", params: slider))
        ])
        let r = TerminalRenderer.render(output, options: plain)
        XCTAssertTrue(r.contains("██████░░░░░░ 50%"), r)
        XCTAssertTrue(r.contains("[on]"), r)
        XCTAssertTrue(r.contains("[off]"), r)
        XCTAssertTrue(r.contains("] 3"), r)     // slider knob track + value
    }

    func testSFSymbolAndImageShownByName() {
        var sf = LineParams(); sf.swiftbar.sfimage = "cpu"
        var img = LineParams(); img.image = "QUJD"     // base64 payload, unrenderable in a terminal
        let output = ParsedOutput(body: [
            .item(MenuItem(text: "CPU", params: sf)),
            .item(MenuItem(text: "Logo", params: img))
        ])
        let r = TerminalRenderer.render(output, options: plain)
        XCTAssertTrue(r.contains("[cpu] CPU"), r)
        XCTAssertTrue(r.contains("[img] Logo"), r)
    }

    func testDisabledAndHeaderRowsHaveNoActionGlyph() {
        var disabled = LineParams(); disabled.href = URL(string: "https://x"); disabled.disabled = true
        var header = LineParams(); header.swiftbar.header = true

        let output = ParsedOutput(body: [
            .item(MenuItem(text: "Section", params: header)),
            .item(MenuItem(text: "Frozen link", params: disabled))
        ])
        let r = TerminalRenderer.render(output, options: plain)
        XCTAssertTrue(r.contains("Section"), r)
        XCTAssertTrue(r.contains("Frozen link"), r)
        XCTAssertFalse(r.contains("↗"), r)   // disabled → not actionable
    }

    // MARK: - Color (SGR)

    func testColorOnEmitsSGRForNamedAndRGB() {
        var green = LineParams(); green.color = .named("green")
        var red = LineParams(); red.color = .rgb(r: 255, g: 0, b: 0, a: 255)
        let output = ParsedOutput(body: [
            .item(MenuItem(text: "ok", params: green)),
            .item(MenuItem(text: "bad", params: red))
        ])
        let r = TerminalRenderer.render(output, options: TerminalRenderer.Options(color: true, width: 80))
        XCTAssertTrue(r.contains("\u{1B}[32mok\u{1B}[0m"), r)
        XCTAssertTrue(r.contains("\u{1B}[38;2;255;0;0mbad\u{1B}[0m"), r)
    }

    func testColorOffEmitsNoEscapes() {
        var green = LineParams(); green.color = .named("green")
        let output = ParsedOutput(titleLines: [TitleLine(text: "T", params: green)], body: [
            .item(MenuItem(text: "ok", params: green))
        ])
        let r = TerminalRenderer.render(output, options: plain)
        XCTAssertFalse(r.contains("\u{1B}["), r)
    }

    func testAnsiRunsRenderAsPerSegmentSGR() {
        let runs = [AnsiRun(range: 0..<1, foreground: .named("red"), bold: true)]
        let styled = TerminalRenderer.styledText(
            "AB", color: nil, runs: runs,
            options: TerminalRenderer.Options(color: true, width: 80))
        XCTAssertTrue(styled.contains("\u{1B}[1;31mA\u{1B}[0m"), styled)
        XCTAssertTrue(styled.hasSuffix("B"), styled)
    }
}
