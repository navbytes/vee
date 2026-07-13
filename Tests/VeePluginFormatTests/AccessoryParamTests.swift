import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native `accessory=` line param, which places a row's
/// `progress=`/`sparkline=` accessory at the leading or trailing edge.
final class AccessoryParamTests: XCTestCase {
    private func parse(_ line: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs)
    }
    // Stored on `params.swiftbar` — see the doc comment on `LineParams.swiftbar`
    // for why (not a SwiftBar param; a workaround for a struct-layout limit).
    private func accessory(_ line: String) -> AccessoryPlacement? { parse(line).params.swiftbar.accessory }

    func testLeading() {
        XCTAssertEqual(accessory("Budget | progress=0.5 accessory=leading"), .leading)
    }

    func testTrailing() {
        XCTAssertEqual(accessory("Budget | progress=0.5 accessory=trailing"), .trailing)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(accessory("x | accessory=LEADING"), .leading)
        XCTAssertEqual(accessory("x | accessory=Trailing"), .trailing)
    }

    func testAbsentIsNil() {
        XCTAssertNil(accessory("Plain | color=red"))
    }

    func testEmptyIsNilWithoutDiagnostic() {
        let r = parse("x | accessory=")
        XCTAssertNil(r.params.swiftbar.accessory)
        XCTAssertFalse(r.diagnostics.contains { $0.message.contains("accessory=") })
    }

    func testInvalidValueIsNilWithDiagnostic() {
        let r = parse("x | accessory=middle")
        XCTAssertNil(r.params.swiftbar.accessory)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("accessory=") })
    }

    /// `accessory=` alone (no progress=/sparkline=) still parses — it simply
    /// has nothing to place, mirroring how `trackcolor=`/`progressw=` parse
    /// independent of `progress=` being present.
    func testAccessoryWithoutVisualParamStillParses() {
        XCTAssertEqual(accessory("x | accessory=leading"), .leading)
    }
}
