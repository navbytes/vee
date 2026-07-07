import XCTest
@testable import VeePluginFormat

final class PluginFeaturesTests: XCTestCase {
    func testEmptyWhenNothingDeclared() {
        let features = PluginFeatures(header: HeaderParser.parse(source: "echo hi\n"))
        XCTAssertTrue(features.isEmpty)
        XCTAssertTrue(features.items.isEmpty)
    }

    func testDerivesSearchPanelAndHotkeyFromHeader() {
        let source = """
        # <vee.filter>true</vee.filter>
        # <vee.shortcut>cmd+shift+k</vee.shortcut>
        """
        let features = PluginFeatures(header: HeaderParser.parse(source: source))
        XCTAssertFalse(features.isEmpty)
        XCTAssertTrue(features.searchPanel)
        XCTAssertEqual(features.hotkey, "⇧⌘K")

        // Search row first, then the hotkey row, with the binding in the detail.
        XCTAssertEqual(features.items.map(\.title), ["Searchable menu", "Global hotkey"])
        XCTAssertTrue(features.items[1].detail.contains("⇧⌘K"))
    }

    func testSearchPanelWithoutHotkey() {
        let features = PluginFeatures(header: HeaderParser.parse(source: "# <vee.filter>true</vee.filter>\n"))
        XCTAssertEqual(features.items.map(\.title), ["Searchable menu"])
        XCTAssertNil(features.hotkey)
    }

    func testInvalidHotkeyDoesNotSurface() {
        // A modifier-less shortcut is rejected at parse time → no hotkey feature.
        let features = PluginFeatures(header: HeaderParser.parse(source: "# <vee.shortcut>k</vee.shortcut>\n"))
        XCTAssertTrue(features.isEmpty)
    }
}
