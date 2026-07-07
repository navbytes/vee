import XCTest
@testable import VeePluginFormat

final class EffectiveHotkeyTests: XCTestCase {
    private let declared = HotKeySpec.parse("cmd+shift+k")!

    func testNoDeclaredHotkeyIsNotControllable() {
        // Even a stray custom binding can't add a hotkey to a plugin that never
        // declared one.
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: nil, userDisabled: false, customBinding: "cmd+shift+j"),
            .none
        )
    }

    func testUsesDeclaredWhenNoOverride() {
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: declared, userDisabled: false, customBinding: nil),
            .use(declared)
        )
    }

    func testUserDisabledWins() {
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: declared, userDisabled: true, customBinding: "cmd+shift+j"),
            .disabled
        )
    }

    func testCustomBindingOverridesDeclared() {
        let custom = HotKeySpec.parse("cmd+shift+j")!
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: declared, userDisabled: false, customBinding: "cmd+shift+j"),
            .use(custom)
        )
    }

    func testInvalidCustomBindingSurfacesInvalid() {
        // A mistyped rebind is reported, not silently reverted to the declared one.
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: declared, userDisabled: false, customBinding: "florb"),
            .invalid
        )
    }

    func testEmptyCustomBindingFallsBackToDeclared() {
        XCTAssertEqual(
            EffectiveHotkey.resolve(declared: declared, userDisabled: false, customBinding: "   "),
            .use(declared)
        )
    }
}
