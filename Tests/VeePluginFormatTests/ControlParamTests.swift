import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native `toggle=`/`slider=` line params that opt an item into
/// the native Liquid Glass interactive-control popover.
final class ControlParamTests: XCTestCase {
    private func params(_ line: String) -> LineParams {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs).params
    }

    // MARK: toggle

    func testToggleOnFromTruthyTokens() {
        for value in ["true", "1", "yes", "on"] {
            XCTAssertEqual(params("Wifi | toggle=\(value)").control, .toggle(on: true), "toggle=\(value)")
        }
    }

    func testToggleOff() {
        for value in ["false", "0", "no", "off"] {
            XCTAssertEqual(params("Wifi | toggle=\(value)").control, .toggle(on: false), "toggle=\(value)")
        }
    }

    func testEmptyToggleIsNil() {
        XCTAssertNil(params("Wifi | toggle=").control)
    }

    // MARK: slider

    func testSliderParsesMinMaxValue() {
        XCTAssertEqual(params("Vol | slider=0,100,42").control, .slider(min: 0, max: 100, value: 42))
    }

    func testSliderClampsValueIntoRange() {
        XCTAssertEqual(params("Vol | slider=0,10,99").control, .slider(min: 0, max: 10, value: 10))
        XCTAssertEqual(params("Vol | slider=0,10,-5").control, .slider(min: 0, max: 10, value: 0))
    }

    func testSliderAcceptsDecimalsAndNegatives() {
        XCTAssertEqual(params("Gain | slider=-1.5,1.5,0.25").control, .slider(min: -1.5, max: 1.5, value: 0.25))
    }

    func testSliderRejectsWrongArity() {
        XCTAssertNil(params("Vol | slider=0,100").control)
        XCTAssertNil(params("Vol | slider=1,2,3,4").control)
    }

    func testSliderRejectsNonAscendingBounds() {
        XCTAssertNil(params("Vol | slider=100,0,50").control)
        XCTAssertNil(params("Vol | slider=5,5,5").control)
    }

    func testSliderMalformedIsNilWithDiagnostic() {
        let (_, pairs, _) = LineParser.splitTextAndParams("Vol | slider=a,b,c")
        let (p, diags) = LineParser.mapParams(pairs)
        XCTAssertNil(p.control)
        XCTAssertTrue(diags.contains { $0.message.contains("slider=") })
    }

    func testAbsentControlIsNil() {
        XCTAssertNil(params("Plain | color=red").control)
    }
}
