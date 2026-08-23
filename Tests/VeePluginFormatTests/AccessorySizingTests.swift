import XCTest
@testable import VeePluginFormat

/// `accessoryw=` / `accessoryh=` — one pair sizing whichever accessory a row
/// carries, and the deprecation path off the six names it replaces.
final class AccessorySizingTests: XCTestCase {
    private func parse(_ line: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs)
    }

    private func warnings(_ line: String) -> [String] {
        parse(line).diagnostics.map(\.message)
    }

    // MARK: - Sizing each accessory

    func testItSizesAGauge() {
        let progress = parse("x | progress=0.5 accessoryw=200 accessoryh=10").params.progress
        XCTAssertEqual(progress?.effectiveWidth, 200)
        XCTAssertEqual(progress?.effectiveHeight, 10)
    }

    func testItSizesASparkline() {
        let style = parse("x | sparkline=1,2,3 accessoryw=140 accessoryh=24").params.swiftbar.sparklineStyle
        XCTAssertEqual(style?.effectiveWidth, 140)
        XCTAssertEqual(style?.effectiveHeight, 24)
    }

    func testItSizesAChart() {
        let chart = parse("x | stackedbar=1,2,3 accessoryw=150").params.swiftbar.chart
        XCTAssertEqual(chart?.inlineSize.width, 150)
    }

    /// A row carries at most one accessory, so one pair can never size two
    /// things — but the fan-out must still reach whichever one was built.
    func testItReachesWhicheverAccessoryTheRowBuilt() {
        XCTAssertEqual(parse("x | progress=0.5 accessoryw=64").params.progress?.effectiveWidth, 64)
        XCTAssertEqual(parse("x | sparkline=1,2 accessoryw=64").params.swiftbar.sparklineStyle?.effectiveWidth, 64)
        XCTAssertEqual(parse("x | pie=1,2 accessoryw=64").params.swiftbar.chart?.inlineSize.width, 64)
    }

    func testARowWithNoAccessoryIsInertAndSilent() {
        let (params, diagnostics) = parse("x | href=https://example.com accessoryw=full")
        XCTAssertNil(params.progress)
        XCTAssertNil(params.swiftbar.chart)
        XCTAssertNil(params.swiftbar.sparklineStyle)
        XCTAssertTrue(diagnostics.isEmpty, "a plugin mid-edit is not a mistake")
    }

    // MARK: - Defaults stay per-accessory

    func testAnUndeclaredSizeFallsBackPerAccessory() {
        XCTAssertEqual(
            parse("x | progress=0.5").params.progress?.effectiveWidth,
            ProgressParams.defaultWidth
        )
        XCTAssertEqual(
            parse("x | sparkline=1,2").params.swiftbar.sparklineStyle?.effectiveWidth ?? SparklineStyle.defaultWidth,
            SparklineStyle.defaultWidth
        )
    }

    // MARK: - full

    func testFullStretchesEachAccessoryThatCan() {
        XCTAssertEqual(parse("x | progress=0.5 accessoryw=full").params.progress?.isFullWidth, true)
        XCTAssertEqual(parse("x | sparkline=1,2 accessoryw=full").params.swiftbar.sparklineStyle?.isFullWidth, true)
        XCTAssertEqual(parse("x | stackedbar=1,2 accessoryw=full").params.swiftbar.chart?.isFullWidth, true)
    }

    /// A circle can only fill a width by growing the row with it, so the
    /// refusal is unchanged — and still reported once, by the format.
    func testFullIsStillRefusedOnACircle() {
        let (params, diagnostics) = parse("x | pie=1,2 accessoryw=full")
        XCTAssertEqual(params.swiftbar.chart?.isFullWidth, false)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("applies to stackedbar=") })
    }

    // MARK: - Deprecation

    func testEveryOldSpellingStillSizesItsAccessory() {
        XCTAssertEqual(parse("x | progress=0.5 progressw=200").params.progress?.effectiveWidth, 200)
        XCTAssertEqual(parse("x | progress=0.5 progressh=10").params.progress?.effectiveHeight, 10)
        XCTAssertEqual(parse("x | sparkline=1,2 sparklinew=140").params.swiftbar.sparklineStyle?.effectiveWidth, 140)
        XCTAssertEqual(parse("x | sparkline=1,2 sparklineh=24").params.swiftbar.sparklineStyle?.effectiveHeight, 24)
        XCTAssertEqual(parse("x | stackedbar=1,2 chartw=150").params.swiftbar.chart?.inlineSize.width, 150)
        XCTAssertEqual(parse("x | stackedbar=1,2 charth=30").params.swiftbar.chart?.inlineSize.height, 30)
    }

    func testEveryOldSpellingNamesItsReplacement() {
        for (line, replacement) in [
            ("x | progress=0.5 progressw=200", "accessoryw="),
            ("x | progress=0.5 progressh=10", "accessoryh="),
            ("x | sparkline=1,2 sparklinew=140", "accessoryw="),
            ("x | sparkline=1,2 sparklineh=24", "accessoryh="),
            ("x | stackedbar=1,2 chartw=150", "accessoryw="),
            ("x | stackedbar=1,2 charth=30", "accessoryh=")
        ] {
            XCTAssertTrue(
                warnings(line).contains { $0.contains(replacement) },
                "\(line) should point at \(replacement)"
            )
        }
    }

    /// The report that prompted this change: `progressw=full` on a stacked bar
    /// is silently ignored, so the plugin looks broken with nothing saying why.
    func testASizeAimedAtTheWrongAccessorySaysSo() {
        let messages = warnings("x | stackedbar=1,2 progressw=full")
        XCTAssertTrue(
            messages.contains { $0.contains("this row draws stackedbar=") },
            "got: \(messages)"
        )
        XCTAssertTrue(messages.contains { $0.contains("had no effect") })
    }

    func testAMatchingOldSpellingDoesNotClaimAMismatch() {
        XCTAssertFalse(warnings("x | progress=0.5 progressw=200").contains { $0.contains("had no effect") })
    }

    // MARK: - New wins over old

    func testTheNewPairWinsOverTheOneItReplaces() {
        let progress = parse("x | progress=0.5 progressw=200 accessoryw=64").params.progress
        XCTAssertEqual(progress?.effectiveWidth, 64)
    }

    func testTheSupersededParameterSaysItWasIgnored() {
        XCTAssertTrue(
            warnings("x | progress=0.5 progressw=200 accessoryw=64").contains { $0.contains("wins") }
        )
    }
}
