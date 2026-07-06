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
