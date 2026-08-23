import XCTest
@testable import VeePluginFormat
@testable import VeeWidgetShared

/// Parses the golden fixtures shared by all three plugin SDKs (plugins/fixtures)
/// and asserts they round-trip through the Swift parser. This ties the SDK's
/// output to the parser: if either drifts, this fails.
final class FixtureRoundTripTests: XCTestCase {
    private func fixturesDirectory() -> URL {
        // .../Tests/VeePluginFormatTests/FixtureRoundTripTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("plugins/fixtures")
    }

    func testCPUFixtureParses() throws {
        let url = fixturesDirectory().appendingPathComponent("cpu.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let output = OutputParser.parse(source)

        // Title line with color + SF Symbol.
        XCTAssertEqual(output.titleLines.first?.text, "CPU 12%")
        XCTAssertEqual(output.titleLines.first?.params.color, .named("green"))
        XCTAssertEqual(output.titleLines.first?.params.swiftbar.sfimage, "cpu")

        // Body: item(href) · separator · submenu(Details) · item(refresh)
        let items = output.body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i }
            return nil
        }
        XCTAssertEqual(items.map(\.text), ["Top processes", "Details", "Refresh"])
        XCTAssertEqual(items[0].params.href?.absoluteString, "https://example.com/procs")
        XCTAssertEqual(items[1].submenu.compactMap { if case .item(let i) = $0 { return i.text } else { return nil } }, ["Load: 1.20", "Cores: 8"])
        XCTAssertEqual(items[2].params.refresh, true)
        XCTAssertTrue(output.body.contains { if case .separator = $0 { return true } else { return false } })
    }

    func testJSONFixtureParses() throws {
        let url = fixturesDirectory().appendingPathComponent("json-demo.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let output = try XCTUnwrap(JSONOutputParser.parse(source))
        XCTAssertEqual(output.titleLines.first?.text, "JSON ✓")
        XCTAssertEqual(output.body.count, 4) // item · separator · submenu · escaping

        // The last item carries the characters the three SDKs' JSON encoders
        // disagree about by default — Python escapes non-ASCII, Go escapes
        // `<`, `>` and `&`. Recovering them intact proves the fixture was
        // written the way JSON.stringify writes it, in whichever SDK produced
        // it, and that the parser reads that spelling back unchanged.
        let items = output.body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i } else { return nil }
        }
        XCTAssertEqual(items.last?.text, "R&D <beta> ✓")
        XCTAssertEqual(items.last?.params.swiftbar.tooltip, "a & b")
    }

    func testRichFixtureParams() throws {
        let url = fixturesDirectory().appendingPathComponent("rich.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let items = OutputParser.parse(source).body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i } else { return nil }
        }
        XCTAssertEqual(items[0].params.swiftbar.markdown, true)
        XCTAssertEqual(items[1].params.swiftbar.badge, "12")
        XCTAssertEqual(items[2].params.swiftbar.symbolize, true)
    }

    /// Closes the SDK→parser loop for the chart builders: the TS/Python/Go SDKs
    /// emit charts.txt, and the Swift parser must recover each shape, its
    /// values, and its labels/colors — including a quoted label list whose
    /// spaces prove the SDK quoting round-trips through a comma-separated value.
    func testChartsFixtureParams() throws {
        let url = fixturesDirectory().appendingPathComponent("charts.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let items = OutputParser.parse(source).body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i } else { return nil }
        }
        XCTAssertEqual(items.map(\.text), ["By category", "By volume", "Budget"])

        let pie = try XCTUnwrap(items[0].params.swiftbar.chart)
        XCTAssertEqual(pie.kind, .pie)
        XCTAssertEqual(pie.values, [45, 30, 25])
        XCTAssertEqual(pie.label(at: 0), "Documents")

        let donut = try XCTUnwrap(items[1].params.swiftbar.chart)
        XCTAssertEqual(donut.kind, .donut)
        XCTAssertEqual(donut.values, [512, 256, 128])
        XCTAssertEqual(donut.label(at: 0), "Macintosh HD")
        XCTAssertEqual(donut.color(at: 1), .named("teal"))
        XCTAssertEqual(items[1].params.swiftbar.tooltip, "896 GB across 3 volumes")

        let bar = try XCTUnwrap(items[2].params.swiftbar.chart)
        XCTAssertEqual(bar.kind, .stackedBar)
        XCTAssertEqual(bar.fraction(at: 0), 0.6, accuracy: 1e-9)
    }

    /// Closes the SDK→parser loop for the typed rich-param builders: the TS/
    /// Python/Go SDKs emit controls.txt, and the Swift parser must recover the
    /// progress fraction, toggle/slider controls, and sparkline series from it.
    func testControlsFixtureParams() throws {
        let url = fixturesDirectory().appendingPathComponent("controls.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let items = OutputParser.parse(source).body.compactMap { node -> MenuItem? in
            if case .item(let i) = node { return i } else { return nil }
        }
        XCTAssertEqual(items.map(\.text), ["Disk usage", "Notifications", "Volume", "Load history"])

        // progress=0.72 with a track color and explicit size; the tooltip's
        // spaces prove the SDK quoting round-trips.
        let progress = try XCTUnwrap(items[0].params.progress)
        XCTAssertEqual(progress.fraction, 0.72, accuracy: 1e-9)
        XCTAssertEqual(progress.trackColor, .rgb(r: 0x33, g: 0x33, b: 0x33, a: 255))
        XCTAssertEqual(progress.width, 80)
        XCTAssertEqual(progress.height, 6)
        XCTAssertEqual(items[0].params.swiftbar.tooltip, "72 GB of 100 GB used")

        // toggle=on
        XCTAssertEqual(items[1].params.control, .toggle(on: true))

        // slider=0,100,40
        XCTAssertEqual(items[2].params.control, .slider(min: 0, max: 100, value: 40))

        // sparkline=1,2,3,5,8,13
        XCTAssertEqual(items[3].params.sparkline, [1, 2, 3, 5, 8, 13])
    }

    /// Closes the SDK→parser loop for the widget surface contract: the TS
    /// SDK's `widget-card` example emits widget-card.txt, and
    /// `WidgetCardParser` must recover the exact card the SDK built it from.
    func testWidgetCardFixtureParses() throws {
        let url = fixturesDirectory().appendingPathComponent("widget-card.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let (card, diagnostics) = WidgetCardParser.parse(source)
        XCTAssertEqual(diagnostics, [])
        let expected = WidgetCard(
            template: .stat,
            title: "Revenue",
            symbol: "chart.line.uptrend.xyaxis",
            tint: .named("green"),
            value: "$18.2k",
            caption: "today",
            detail: "214 orders",
            status: .ok,
            progress: 0.72,
            trend: [12.1, 13.4, 12.9, 15.0, 18.2],
            items: [
                WidgetCardItem(label: "Orders", value: "214", symbol: "bag", tint: .named("blue")),
                WidgetCardItem(label: "Refunds", value: "3", symbol: "arrow.uturn.left", tint: .named("red"))
            ],
            actions: [
                WidgetCardAction(kind: .refresh, label: "Refresh"),
                WidgetCardAction(kind: .href, label: "Open", url: "https://dash.example.com")
            ],
            refreshAfter: 900,
            staleAfter: 3600
        )
        XCTAssertEqual(card, expected)
    }

    /// Closes the SDK→parser loop for the layout tree: the `widget-layout`
    /// example (byte-identical across the TS/Python/Go SDKs) emits
    /// widget-layout.txt, and `WidgetCardParser` must recover the exact tree —
    /// the same node vocabulary, the two pressure-test modifiers
    /// (`monospaced_digit`/`min_scale`), and the circular gauge — with no
    /// diagnostics (a clean tree trips no guardrail).
    func testWidgetLayoutFixtureParses() throws {
        let url = fixturesDirectory().appendingPathComponent("widget-layout.txt")
        let source = try String(contentsOf: url, encoding: .utf8)
        let (card, diagnostics) = WidgetCardParser.parse(source)
        XCTAssertEqual(diagnostics, [])

        let expected = WidgetNode(type: "vstack", align: "leading", spacing: 6, children: [
            WidgetNode(type: "hstack", spacing: 5, children: [
                WidgetNode(type: "image", symbol: "cpu", style: WidgetNodeStyle(tint: .named("blue"))),
                WidgetNode(type: "text", text: "CPU", style: WidgetNodeStyle(
                    font: WidgetNodeFont(size: "caption", weight: "semibold"), tint: .named("secondary"))),
                WidgetNode(type: "spacer")
            ]),
            WidgetNode(type: "text", text: "38%", style: WidgetNodeStyle(
                font: WidgetNodeFont(size: "title", design: "rounded"),
                tint: .named("green"), monospacedDigit: true, minScale: 0.6)),
            WidgetNode(type: "gauge", value: 0.38, gaugeStyle: "circular", style: WidgetNodeStyle(tint: .named("green")))
        ])
        XCTAssertEqual(card?.layout, expected)
        // A pure-layout card still gets the default template.
        XCTAssertEqual(card?.template, .stat)
    }
}
