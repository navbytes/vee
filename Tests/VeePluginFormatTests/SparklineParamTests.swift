import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native `sparkline=` line param that opts an item into the
/// native Liquid Glass Swift Charts popover.
final class SparklineParamTests: XCTestCase {
    private func params(_ line: String) -> LineParams {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs).params
    }

    func testParsesCommaSeparatedDoubles() {
        XCTAssertEqual(params("CPU | sparkline=1,2,3,4,5").sparkline, [1, 2, 3, 4, 5])
    }

    func testParsesDecimalsAndNegatives() {
        XCTAssertEqual(params("Temp | sparkline=1.5,-2,3.25").sparkline, [1.5, -2, 3.25])
    }

    func testSkipsMalformedEntries() {
        // Non-numeric and empty entries are dropped, valid ones kept.
        XCTAssertEqual(params("Mixed | sparkline=1,x,3,,5").sparkline, [1, 3, 5])
    }

    func testEmptyValueYieldsNil() {
        XCTAssertNil(params("Empty | sparkline=").sparkline)
    }

    func testAllMalformedYieldsNil() {
        XCTAssertNil(params("Bad | sparkline=a,b,c").sparkline)
    }

    func testAbsentParamIsNil() {
        XCTAssertNil(params("Plain | color=red").sparkline)
    }
}
