import XCTest
@testable import VeePluginFormat

final class CompactNumberTests: XCTestCase {
    func testWholeNumbersPrintBare() {
        XCTAssertEqual(CompactNumber.label(42), "42")
        XCTAssertEqual(CompactNumber.label(-7), "-7")
        XCTAssertEqual(CompactNumber.label(0), "0")
    }

    func testFractionsPrintTwoDecimals() {
        XCTAssertEqual(CompactNumber.label(3.14159), "3.14")
        XCTAssertEqual(CompactNumber.label(-0.5), "-0.50")
    }

    /// V2-review S1 regression: `String(Int(v))` traps on any finite value
    /// ≥ ~9.2e18, and these values arrive straight from plugin output
    /// (`sparkline=1,2,1e19`). The label must degrade, never abort.
    func testHugeFiniteValuesDoNotTrap() {
        XCTAssertEqual(CompactNumber.label(1e19), String(format: "%.2f", 1e19))
        XCTAssertEqual(CompactNumber.label(-1e19), String(format: "%.2f", -1e19))
        XCTAssertEqual(CompactNumber.label(Double.greatestFiniteMagnitude),
                       String(format: "%.2f", Double.greatestFiniteMagnitude))
    }

    func testLargestExactlyRepresentableWholeStaysBare() {
        // 2^62 is a whole Double well inside Int range — must stay bare.
        XCTAssertEqual(CompactNumber.label(4611686018427387904.0), "4611686018427387904")
    }
}
