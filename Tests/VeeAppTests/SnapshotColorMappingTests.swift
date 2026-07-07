import XCTest
@testable import VeeApp
import VeePluginFormat
import VeeWidgetShared

/// Covers the app-side bridge from the parser's `VeeColor` to the Foundation-only
/// `SnapshotColor` the widget snapshot carries (VeeWidgetShared can't see VeeColor).
final class SnapshotColorMappingTests: XCTestCase {
    func testMapsNamed() {
        XCTAssertEqual(WidgetSnapshotMapping.snapshotColor(.named("green")), .named("green"))
    }

    func testMapsRGBA() {
        XCTAssertEqual(
            WidgetSnapshotMapping.snapshotColor(.rgb(r: 10, g: 20, b: 30, a: 200)),
            .rgba(r: 10, g: 20, b: 30, a: 200)
        )
    }

    func testMapsOptionalArray() {
        XCTAssertNil(WidgetSnapshotMapping.snapshotColors(nil))
        XCTAssertEqual(
            WidgetSnapshotMapping.snapshotColors([.named("red"), .rgb(r: 0, g: 0, b: 0, a: 255)]),
            [.named("red"), .rgba(r: 0, g: 0, b: 0, a: 255)]
        )
    }
}
