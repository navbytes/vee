import XCTest
@testable import VeeWidgetShared

/// Covers `SnapshotColor` — the Foundation-only color the app publishes to the
/// widget (VeeWidgetShared must not depend on VeePluginFormat's `VeeColor`).
final class SnapshotColorTests: XCTestCase {
    func testParsesNamedColorLowercased() {
        XCTAssertEqual(SnapshotColor.parse("Red"), .named("red"))
        XCTAssertEqual(SnapshotColor.parse("  labelColor "), .named("labelcolor"))
    }

    func testParsesShortHex() {
        XCTAssertEqual(SnapshotColor.parse("#f00"), .rgba(r: 255, g: 0, b: 0, a: 255))
    }

    func testParsesSixDigitHex() {
        XCTAssertEqual(SnapshotColor.parse("#00ff80"), .rgba(r: 0, g: 255, b: 128, a: 255))
    }

    func testParsesEightDigitHexWithAlpha() {
        XCTAssertEqual(SnapshotColor.parse("#11223344"), .rgba(r: 0x11, g: 0x22, b: 0x33, a: 0x44))
    }

    func testRejectsEmptyAndMalformedHex() {
        XCTAssertNil(SnapshotColor.parse(""))
        XCTAssertNil(SnapshotColor.parse("   "))
        XCTAssertNil(SnapshotColor.parse("#xyz"))
        XCTAssertNil(SnapshotColor.parse("#12"))
    }

    func testStringValueRoundTrips() {
        for color: SnapshotColor in [.named("teal"), .rgba(r: 1, g: 2, b: 3, a: 4), .rgba(r: 255, g: 128, b: 0, a: 255)] {
            XCTAssertEqual(SnapshotColor.parse(color.stringValue), color, color.stringValue)
        }
    }

    func testEncodesAsSingleStringValue() throws {
        let data = try JSONEncoder().encode(SnapshotColor.rgba(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"#ff0000ff\"")
    }

    func testCodableRoundTrips() throws {
        let colors: [SnapshotColor] = [.named("systemred"), .rgba(r: 10, g: 20, b: 30, a: 200)]
        let data = try JSONEncoder().encode(colors)
        XCTAssertEqual(try JSONDecoder().decode([SnapshotColor].self, from: data), colors)
    }
}
