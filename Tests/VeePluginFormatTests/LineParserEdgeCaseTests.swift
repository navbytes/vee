import XCTest
@testable import VeePluginFormat

/// Edge cases in the `key=value` parameter parser and its mapping onto
/// `LineParams` — the kinds of malformed/hostile plugin output that must not
/// crash or silently lose data.
final class LineParserEdgeCaseTests: XCTestCase {
    private func params(_ s: String) -> LineParams {
        LineParser.mapParams(LineParser.parseParams(s).pairs).params
    }

    // MARK: length

    /// A negative `length=` must never reach `String.prefix(_:)` (which traps on
    /// a negative argument and crashes the whole menu-bar app). Clamp at parse.
    func testNegativeLengthClampsToZero() {
        XCTAssertEqual(params("length=-1").length, 0)
        XCTAssertEqual(params("length=-999").length, 0)
    }

    func testZeroAndPositiveLengthPreserved() {
        XCTAssertEqual(params("length=0").length, 0)
        XCTAssertEqual(params("length=5").length, 5)
    }

    func testNonNumericLengthIsNil() {
        XCTAssertNil(params("length=abc").length)
    }

    // MARK: tab-separated params

    /// A tab between a bare value and the next key must terminate the value —
    /// otherwise the tab and everything after it is swallowed into the value and
    /// the following params are lost.
    func testTabTerminatesBareValue() {
        let parsed = LineParser.parseParams("color=red\tsize=14")
        let dict = Dictionary(parsed.pairs, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["color"], "red")
        XCTAssertEqual(dict["size"], "14")
    }

    func testSpaceStillSeparatesParams() {
        let parsed = LineParser.parseParams("color=red size=14")
        let dict = Dictionary(parsed.pairs, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["color"], "red")
        XCTAssertEqual(dict["size"], "14")
    }
}
