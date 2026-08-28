import XCTest
@testable import VeePluginFormat

/// Bounds on what a single run of plugin stdout can turn into. Every value here
/// arrives from a subprocess Vee doesn't control, and each one reaches AppKit
/// more or less directly.
final class OutputBoundsTests: XCTestCase {
    private func params(_ line: String) -> LineParams {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs).params
    }

    // MARK: - Row count

    func testRunawayOutputIsTruncatedWithAWarning() {
        let runaway = (0..<5000).map { "Row \($0)" }.joined(separator: "\n")
        let parsed = OutputParser.parse("Title\n---\n" + runaway)
        XCTAssertLessThan(parsed.body.count, 5000, "a runaway plugin must not build 5000 menu items")
        XCTAssertTrue(parsed.diagnostics.contains { $0.message.contains("truncated") },
                      "truncation must be reported, never silent")
    }

    func testAnOrdinaryMenuIsNotTruncated() {
        let ordinary = (0..<200).map { "Row \($0)" }.joined(separator: "\n")
        let parsed = OutputParser.parse("Title\n---\n" + ordinary)
        XCTAssertEqual(parsed.body.count, 200)
        XCTAssertFalse(parsed.diagnostics.contains { $0.message.contains("truncated") },
                       "a long-but-reasonable menu must be left alone")
    }

    // MARK: - Font sizes

    /// `size=`/`sfsize=` reach `NSFont.systemFont(ofSize:)` and a symbol
    /// configuration directly, and a menu row grows to fit its text.
    func testFontSizesAreClamped() {
        XCTAssertEqual(params("x | size=1000000").size, FontSizeLimit.range.upperBound)
        XCTAssertEqual(params("x | size=-20").size, FontSizeLimit.range.lowerBound)
        XCTAssertEqual(params("x | sfsize=999999").swiftbar.sfsize, FontSizeLimit.range.upperBound)
        XCTAssertEqual(params("x | sfsize=0").swiftbar.sfsize, FontSizeLimit.range.lowerBound)
    }

    func testOrdinaryFontSizesPassThroughUnchanged() {
        XCTAssertEqual(params("x | size=13").size, 13)
        XCTAssertEqual(params("x | size=48").size, 48, "a deliberately large title must not be clipped")
        XCTAssertEqual(params("x | sfsize=18").swiftbar.sfsize, 18)
    }

    /// NaN defeats min/max, so the parser must reject it before any clamp runs.
    func testNonFiniteFontSizesAreStillRejected() {
        XCTAssertNil(params("x | size=nan").size)
        XCTAssertNil(params("x | sfsize=inf").swiftbar.sfsize)
    }
}
