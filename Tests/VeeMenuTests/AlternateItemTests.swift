import AppKit
import XCTest
@testable import VeeMenu
import VeePluginFormat

/// `alternate=true` in the built `NSMenu`.
///
/// AppKit shows an alternate in place of its predecessor only when the two
/// carry the **same key equivalent** and differ in modifier mask. Get that
/// wrong and there is no error and no warning — the menu simply renders both
/// rows at once and ⌥ does nothing, which is exactly how this shipped
/// unnoticed. These assertions pin the invariant rather than the symptom.
@MainActor
final class AlternateItemTests: XCTestCase {
    private final class Target: MenuActionHandling {
        func perform(_ item: MenuItem) {}
        func commitControl(_ item: MenuItem, value: Double) {}
    }

    private func menu(_ main: MenuItem) -> NSMenu {
        MenuBuilder.build([.item(main)], target: MenuActionTarget(handler: Target()))
    }

    private func pair(primaryKey: String?, alternateKey: String? = nil) -> (primary: NSMenuItem, alternate: NSMenuItem) {
        var mainParams = LineParams()
        mainParams.refresh = true
        mainParams.key = primaryKey
        var altParams = LineParams()
        altParams.refresh = true
        altParams.key = alternateKey

        var main = MenuItem(text: "Refresh", params: mainParams)
        main.alternate = MenuItem(text: "Force Refresh", params: altParams)

        let items = menu(main).items
        precondition(items.count == 2, "expected a primary and its alternate, got \(items.count)")
        return (items[0], items[1])
    }

    func testTheAlternateIsMarkedAsSuch() {
        let (primary, alternate) = pair(primaryKey: nil)
        XCTAssertFalse(primary.isAlternate)
        XCTAssertTrue(alternate.isAlternate)
    }

    /// The regression this suite exists for: a primary declaring `key=` used to
    /// leave its alternate with an empty key equivalent, so AppKit could not
    /// pair them and drew both rows permanently.
    func testAPrimaryWithAKeyLendsItToItsAlternate() {
        let (primary, alternate) = pair(primaryKey: "r")
        XCTAssertEqual(primary.keyEquivalent, "r")
        XCTAssertEqual(alternate.keyEquivalent, primary.keyEquivalent, "AppKit pairs them only when the keys match")
        XCTAssertNotEqual(
            alternate.keyEquivalentModifierMask, primary.keyEquivalentModifierMask,
            "…and only when the masks differ"
        )
        XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.option))
    }

    func testAKeylessPrimaryStillPairsWithItsAlternate() {
        let (primary, alternate) = pair(primaryKey: nil)
        XCTAssertEqual(alternate.keyEquivalent, primary.keyEquivalent)
        XCTAssertNotEqual(alternate.keyEquivalentModifierMask, primary.keyEquivalentModifierMask)
        XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.option))
    }

    /// An alternate cannot carry a key equivalent of its own, so a plugin that
    /// declares one must not be allowed to break the pairing with it.
    func testAnAlternatesOwnKeyCannotBreakThePairing() {
        let (primary, alternate) = pair(primaryKey: "r", alternateKey: "f")
        XCTAssertEqual(alternate.keyEquivalent, primary.keyEquivalent)
        XCTAssertNotEqual(alternate.keyEquivalentModifierMask, primary.keyEquivalentModifierMask)
    }

    /// A primary declaring a modified key keeps the pairing: the alternate adds
    /// ⌥ on top rather than replacing the modifiers.
    func testAModifiedPrimaryKeyKeepsThePairing() {
        let (primary, alternate) = pair(primaryKey: "cmd+r")
        XCTAssertEqual(alternate.keyEquivalent, primary.keyEquivalent)
        XCTAssertNotEqual(alternate.keyEquivalentModifierMask, primary.keyEquivalentModifierMask)
        XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.option))
        XCTAssertTrue(alternate.keyEquivalentModifierMask.contains(.command))
    }
}
