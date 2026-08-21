import XCTest
@testable import VeePluginFormat

final class HotkeyPresentationTests: XCTestCase {
    func testDefaultIsTheTransientPanel() {
        XCTAssertEqual(HotkeyPresentation.default, .panel)
    }

    /// A plugin that declared `<vee.shortcut>` before this choice existed has no
    /// stored value, and must keep doing exactly what it did.
    func testAnAbsentPreferenceResolvesToTheDefault() {
        XCTAssertEqual(HotkeyPresentation.resolve(nil), .panel)
    }

    /// A preference read must never be able to leave a plugin with no working
    /// hotkey, so an unrecognised value falls back rather than failing.
    func testAnUnrecognisedValueResolvesToTheDefault() {
        XCTAssertEqual(HotkeyPresentation.resolve("sidebar"), .panel)
        XCTAssertEqual(HotkeyPresentation.resolve(""), .panel)
    }

    func testStoredValuesRoundTrip() {
        for presentation in HotkeyPresentation.allCases {
            XCTAssertEqual(HotkeyPresentation.resolve(presentation.rawValue), presentation)
        }
    }
}
