import XCTest
@testable import VeePluginFormat

final class NumericInputTests: XCTestCase {
    func testStripsLettersAndSymbols() {
        XCTAssertEqual(NumericInput.sanitize("12a3!"), "123")
        XCTAssertEqual(NumericInput.sanitize("$5.00"), "5.00")
    }

    func testKeepsLeadingMinusOnly() {
        XCTAssertEqual(NumericInput.sanitize("-42"), "-42")
        // A minus not at the front is dropped.
        XCTAssertEqual(NumericInput.sanitize("4-2"), "42")
        XCTAssertEqual(NumericInput.sanitize("--5"), "-5")
    }

    func testAllowsAtMostOneDecimalPoint() {
        XCTAssertEqual(NumericInput.sanitize("3.14"), "3.14")
        XCTAssertEqual(NumericInput.sanitize("3.1.4"), "3.14")
    }

    func testPreservesPartialInputWhileTyping() {
        XCTAssertEqual(NumericInput.sanitize("-"), "-")
        XCTAssertEqual(NumericInput.sanitize("1."), "1.")
        XCTAssertEqual(NumericInput.sanitize(""), "")
    }

    func testDropsNonASCIIDigits() {
        // Arabic-Indic digits and fraction glyphs are not accepted.
        XCTAssertEqual(NumericInput.sanitize("٤٢"), "")
        XCTAssertEqual(NumericInput.sanitize("½"), "")
    }
}
