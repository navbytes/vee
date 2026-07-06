import XCTest
@testable import VeeApp
import VeePluginFormat

/// Covers `PluginCoordinator.publishableTitle`, the sole source of the per-plugin
/// text shown in the WidgetKit widget.
@MainActor
final class PublishableTitleTests: XCTestCase {
    private func title(_ lines: [TitleLine]) -> String {
        PluginCoordinator.publishableTitle(ParsedOutput(titleLines: lines, body: []))
    }

    func testEmptyOutputYieldsEmptyString() {
        XCTAssertEqual(title([]), "")
    }

    func testUsesFirstTitleLine() {
        XCTAssertEqual(title([TitleLine(text: "CPU 42%"), TitleLine(text: "second")]), "CPU 42%")
    }

    func testTrimsSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(title([TitleLine(text: "  ↓ 1.2 MB/s \n")]), "↓ 1.2 MB/s")
    }

    func testAllWhitespaceTitleBecomesEmpty() {
        XCTAssertEqual(title([TitleLine(text: "   \t")]), "")
    }
}
