import XCTest
@testable import VeePluginFormat

/// `accessoryWidth` / `accessoryHeight` in structured output — the JSON
/// counterpart of `accessoryw=`/`accessoryh=`, held to the same contract so a
/// plugin behaves identically whichever format it emits.
final class AccessorySizingJSONTests: XCTestCase {
    private func parse(_ item: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let json = #"{"vee":1,"title":[{"text":"T"}],"items":[\#(item)]}"#
        let out = OutputParser.parseAuto(json)
        guard case .item(let menuItem)? = out.body.first else {
            return (LineParams(), out.diagnostics)
        }
        return (menuItem.params, out.diagnostics)
    }

    private func warnings(_ item: String) -> [String] { parse(item).diagnostics.map(\.message) }

    // MARK: - Sizing each accessory

    func testItSizesAGauge() {
        let progress = parse(#"{"text":"a","progress":0.5,"accessoryWidth":200,"accessoryHeight":10}"#).params.progress
        XCTAssertEqual(progress?.effectiveWidth, 200)
        XCTAssertEqual(progress?.effectiveHeight, 10)
    }

    func testItSizesASparkline() {
        let style = parse(#"{"text":"a","sparkline":[1,2,3],"accessoryWidth":140,"accessoryHeight":24}"#)
            .params.swiftbar.sparklineStyle
        XCTAssertEqual(style?.effectiveWidth, 140)
        XCTAssertEqual(style?.effectiveHeight, 24)
    }

    func testItSizesAChart() {
        let chart = parse(#"{"text":"a","chart":{"kind":"stackedbar","values":[1,2]},"accessoryWidth":150}"#)
            .params.swiftbar.chart
        XCTAssertEqual(chart?.inlineSize.width, 150)
    }

    func testItSizesASlider() {
        let params = parse(#"{"text":"a","slider":{"min":0,"max":100,"value":40},"accessoryWidth":120}"#).params
        XCTAssertEqual(params.controlWidth, 120)
    }

    // MARK: - full

    func testFullStretches() {
        XCTAssertEqual(
            parse(#"{"text":"a","progress":0.5,"accessoryWidth":"full"}"#).params.progress?.isFullWidth,
            true
        )
        XCTAssertEqual(
            parse(#"{"text":"a","chart":{"kind":"stackedbar","values":[1,2]},"accessoryWidth":"full"}"#)
                .params.swiftbar.chart?.isFullWidth,
            true
        )
    }

    func testFullIsStillRefusedOnACircle() {
        let (params, diagnostics) = parse(#"{"text":"a","chart":{"kind":"pie","values":[1,2]},"accessoryWidth":"full"}"#)
        XCTAssertEqual(params.swiftbar.chart?.isFullWidth, false)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("applies to stackedbar=") })
    }

    // MARK: - Deprecation

    func testTheSupersededFieldsStillSize() {
        XCTAssertEqual(
            parse(#"{"text":"a","progress":0.5,"progressWidth":200}"#).params.progress?.effectiveWidth,
            200
        )
        XCTAssertEqual(
            parse(#"{"text":"a","sparkline":[1,2],"sparklineWidth":140}"#).params.swiftbar.sparklineStyle?.effectiveWidth,
            140
        )
        XCTAssertEqual(
            parse(#"{"text":"a","chart":{"kind":"stackedbar","values":[1,2],"w":150}}"#).params.swiftbar.chart?.inlineSize.width,
            150
        )
    }

    func testTheSupersededFieldsNameTheirReplacement() {
        XCTAssertTrue(warnings(#"{"text":"a","progress":0.5,"progressWidth":200}"#)
            .contains { $0.contains("accessoryWidth") })
        XCTAssertTrue(warnings(#"{"text":"a","sparkline":[1,2],"sparklineHeight":24}"#)
            .contains { $0.contains("accessoryHeight") })
        XCTAssertTrue(warnings(#"{"text":"a","chart":{"kind":"stackedbar","values":[1,2],"w":150}}"#)
            .contains { $0.contains("chart.w") })
    }

    func testTheNewFieldWinsOverTheOneItReplaces() {
        let progress = parse(#"{"text":"a","progress":0.5,"progressWidth":200,"accessoryWidth":64}"#).params.progress
        XCTAssertEqual(progress?.effectiveWidth, 64)
        XCTAssertTrue(warnings(#"{"text":"a","progress":0.5,"progressWidth":200,"accessoryWidth":64}"#)
            .contains { $0.contains("wins") })
    }

    // MARK: - Parity with the text format

    /// The two formats produce the same model — the whole reason `parseAuto`
    /// can hand either to the same renderers.
    func testJSONAndTextAgree() {
        let fromJSON = parse(#"{"text":"a","progress":0.5,"accessoryWidth":"full","accessoryHeight":10}"#).params
        let (_, pairs, _) = LineParser.splitTextAndParams("a | progress=0.5 accessoryw=full accessoryh=10")
        let fromText = LineParser.mapParams(pairs).params
        XCTAssertEqual(fromJSON.progress?.isFullWidth, fromText.progress?.isFullWidth)
        XCTAssertEqual(fromJSON.progress?.effectiveHeight, fromText.progress?.effectiveHeight)
    }
}
