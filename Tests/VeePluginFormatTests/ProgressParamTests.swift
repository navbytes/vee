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
}
