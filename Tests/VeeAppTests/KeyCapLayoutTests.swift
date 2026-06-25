import XCTest
import AppKit
@testable import VeeApp

/// Regression for the UI-2 key-cap layout bug found during audit convergence: a
/// single-glyph cap inside the trailing-pinned `shortcutStack` was floating wide
/// (a half-row grey pill) because its width was bounded only by `>=` floors with
/// no downward pressure. The cap must hug its glyph.
final class KeyCapLayoutTests: XCTestCase {

    @MainActor
    func testSingleGlyphCapHugsItsGlyphAndDoesNotStretch() {
        let cap = KeyCapView("⌘")
        cap.layoutSubtreeIfNeeded()
        let w = cap.fittingSize.width
        XCTAssertGreaterThanOrEqual(w, 22, "stays above the ↩/⌘K parity floor")
        XCTAssertLessThan(w, 44, "a one-glyph cap must hug its glyph, not stretch into a pill")
    }

    @MainActor
    func testTwoGlyphCapsStayCompact() {
        // The essentials "cmd+enter" shortcut renders as two caps; together they
        // should be a compact hint, nowhere near a half-row pill.
        let total = KeyCapView("⌘").fittingSize.width + KeyCapView("⏎").fittingSize.width
        XCTAssertLessThan(total, 100, "a two-cap shortcut hint must remain compact")
    }
}
