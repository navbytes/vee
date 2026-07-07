import XCTest
@testable import VeePluginFormat

final class HotKeySpecTests: XCTestCase {
    func testParsesModifiersAndKeyOrderIndependently() {
        let a = HotKeySpec.parse("cmd+shift+k")
        let b = HotKeySpec.parse("shift+cmd+k")   // order-independent
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.keyCode, 0x28)           // kVK_ANSI_K
        XCTAssertEqual(a?.modifiers, HotKeySpec.cmdKey | HotKeySpec.shiftKey)
        XCTAssertEqual(a?.display, "⇧⌘K")
    }

    func testModifierAliasesAndSeparators() {
        // command/option/control long names, and `-` as a separator.
        let spec = HotKeySpec.parse("control-option-space")
        XCTAssertEqual(spec?.keyCode, 0x31)        // space
        XCTAssertEqual(spec?.modifiers, HotKeySpec.controlKey | HotKeySpec.optionKey)
        XCTAssertEqual(spec?.display, "⌃⌥␣")
    }

    func testCaseInsensitiveAndFunctionKeys() {
        let spec = HotKeySpec.parse("CMD+F5")
        XCTAssertEqual(spec?.keyCode, 0x60)        // kVK_F5
        XCTAssertEqual(spec?.modifiers, HotKeySpec.cmdKey)
    }

    func testRejectsNoModifier() {
        // A bare key would shadow normal typing system-wide — reject it.
        XCTAssertNil(HotKeySpec.parse("k"))
        XCTAssertNil(HotKeySpec.parse("space"))
    }

    func testRejectsUnknownAndMultipleKeys() {
        XCTAssertNil(HotKeySpec.parse("cmd+florb"))     // unknown key
        XCTAssertNil(HotKeySpec.parse("cmd+k+j"))       // two keys
        XCTAssertNil(HotKeySpec.parse(""))              // empty
        XCTAssertNil(HotKeySpec.parse("cmd"))           // modifier only
    }

    func testSymbolModifiers() {
        let spec = HotKeySpec.parse("⌘⌥j")
        XCTAssertEqual(spec?.keyCode, 0x26)             // kVK_ANSI_J
        XCTAssertEqual(spec?.modifiers, HotKeySpec.cmdKey | HotKeySpec.optionKey)
    }
}
