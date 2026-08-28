import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native `progress=` line param (inline gauge) and its
/// `trackcolor=`/`progressw=`/`progressh=` companions.
final class ProgressParamTests: XCTestCase {
    private func parse(_ line: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs)
    }
    private func progress(_ line: String) -> ProgressParams? { parse(line).params.progress }

    func testFractionForm() {
        XCTAssertEqual(progress("Budget | progress=0.72")?.fraction, 0.72)
    }

    func testValueMaxForm() {
        XCTAssertEqual(progress("Budget | progress=19.88,100")?.fraction ?? -1, 0.1988, accuracy: 1e-9)
        XCTAssertEqual(progress("Budget | progress=50,100")?.fraction, 0.5)
    }

    func testClampsIntoUnitRange() {
        XCTAssertEqual(progress("x | progress=5")?.fraction, 1.0)        // single >1 → full
        XCTAssertEqual(progress("x | progress=-0.5")?.fraction, 0.0)
        XCTAssertEqual(progress("x | progress=150,100")?.fraction, 1.0)  // value>max → full
    }

    func testCompanionParams() {
        let p = progress("x | progress=0.5 trackcolor=#3C4046 progressw=140 progressh=8")
        XCTAssertEqual(p?.fraction, 0.5)
        XCTAssertEqual(p?.trackColor, VeeColor.parse("#3C4046"))
        XCTAssertEqual(p?.width, 140)
        XCTAssertEqual(p?.height, 8)
    }

    func testMalformedIsNilWithDiagnostic() {
        let r = parse("x | progress=abc")
        XCTAssertNil(r.params.progress)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("progress=") })
    }

    func testDivideByZeroMaxIsMalformed() {
        XCTAssertNil(progress("x | progress=5,0"))
    }

    func testEmptyAndAbsentAreNil() {
        XCTAssertNil(progress("x | progress="))
        XCTAssertNil(progress("x | color=red"))
    }

    func testCompanionsWithoutProgressYieldNil() {
        // trackcolor/width/height alone don't create a gauge.
        XCTAssertNil(progress("x | trackcolor=red progressw=100"))
    }

    /// Regression: `Double("nan")`/`Double("inf")` parse successfully and NaN
    /// defeats the min/max clamp, producing NaN bar geometry / NSFont sizes from
    /// plugin output. Non-finite numeric params must be rejected at the parser.
    func testNonFiniteProgressRejected() {
        // `nan/2` previously survived the clamp; must now be nil (malformed).
        XCTAssertNil(progress("x | progress=nan,2"))
        XCTAssertNil(progress("x | progress=nan"))
        XCTAssertNil(progress("x | progress=inf"))
        // A finite value alongside non-finite companions keeps the fraction but
        // drops the poisoned width/height.
        let p = progress("x | progress=0.5 progressw=nan progressh=inf")
        XCTAssertEqual(p?.fraction, 0.5)
        XCTAssertNil(p?.width)
        XCTAssertNil(p?.height)
    }

    /// `progressw=full` is the same knob `chartw=full` is, spelled for the
    /// gauge: a stretch flag, not a width, so it must not also land in `width`.
    func testFullWidth() {
        let full = progress("Disk | progress=0.5 progressw=full")
        XCTAssertTrue(full?.isFullWidth == true)
        XCTAssertNil(full?.width)
        XCTAssertEqual(full?.effectiveWidth, ProgressParams.defaultWidth)  // the too-narrow fallback

        let fixed = progress("Disk | progress=0.5 progressw=80")
        XCTAssertFalse(fixed?.isFullWidth == true)
        XCTAssertEqual(fixed?.width, 80)
        XCTAssertFalse(progress("Disk | progress=0.5")?.isFullWidth == true)
    }

    /// `MenuBuilder` passes these straight into a `CGRect` on a live
    /// `NSMenuItem.view`, so an unclamped `progressh=1000000000` is a row taller
    /// than the screen and a negative one is a negative-width rect. `chartw=`
    /// has been clamped for exactly this reason; `progress=`/`sparkline=` were
    /// the two accessories that weren't.
    func testProgressAndSparklineSizesAreClamped() {
        XCTAssertEqual(progress("x | progress=0.5 progressw=1000000000")?.width, ChartParams.sizeLimit.upperBound)
        XCTAssertEqual(progress("x | progress=0.5 progressh=1000000010")?.height, ChartParams.sizeLimit.upperBound)
        XCTAssertEqual(progress("x | progress=0.5 progressw=-40")?.width, ChartParams.minimumSize)

        let spark = parse("x | sparkline=1,2,3 sparklinew=99999 sparklineh=-1").params.swiftbar.sparklineStyle
        XCTAssertEqual(spark?.width, ChartParams.sizeLimit.upperBound)
        XCTAssertEqual(spark?.height, ChartParams.minimumSize)

        // `accessoryw=` fans out to whichever accessory the row carries, so it
        // must land inside the same bounds however it is spelled.
        XCTAssertEqual(progress("x | progress=0.5 accessoryw=5000")?.width, ChartParams.sizeLimit.upperBound)
    }

    /// The clamp must not move a value anyone would actually write — including
    /// a bar thinner than a chart's legibility floor of 8, which is what the
    /// default height already is.
    func testOrdinaryProgressSizesPassThroughUnchanged() {
        XCTAssertEqual(progress("x | progress=0.5 progressh=6")?.height, 6)
        XCTAssertEqual(progress("x | progress=0.5 progressh=\(ProgressParams.defaultHeight)")?.height, ProgressParams.defaultHeight)
        XCTAssertEqual(progress("x | progress=0.5 progressw=180")?.width, 180)
    }

    func testNonFiniteSizeAndSparklineAndSliderRejected() {
        XCTAssertNil(parse("x | size=nan").params.size)
        XCTAssertNil(parse("x | size=inf").params.size)
        XCTAssertNil(parse("x | sfsize=nan").params.swiftbar.sfsize)
        // Non-finite sparkline samples are dropped; an all-bad series is nil.
        XCTAssertNil(parse("x | sparkline=nan,inf").params.sparkline)
        XCTAssertEqual(parse("x | sparkline=1,nan,3").params.sparkline, [1, 3])
        // A slider with a non-finite bound has < 3 finite numbers → no control.
        XCTAssertNil(parse("x | slider=0,inf,5").params.control)
    }
}
