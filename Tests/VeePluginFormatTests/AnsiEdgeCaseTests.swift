import XCTest
@testable import VeePluginFormat

/// ANSI parsing edge cases — in particular non-SGR CSI sequences (cursor moves,
/// erases) which must be stripped without eating surrounding text.
final class AnsiEdgeCaseTests: XCTestCase {
    func testStripsNonSGREraseSequence() {
        // `ESC[K` (erase-to-end-of-line) is not an SGR (`…m`) sequence. It must be
        // removed, not treated as an SGR whose parameters run until the next `m`.
        let (plain, runs) = Ansi.parse("\u{1B}[Kfoo more")
        XCTAssertEqual(plain, "foo more")
        XCTAssertTrue(runs.isEmpty)
    }

    func testStripsParameterizedNonSGRSequence() {
        let (plain, _) = Ansi.parse("\u{1B}[2Kfoo")
        XCTAssertEqual(plain, "foo")
    }

    func testNonSGRDoesNotConsumeUntilLaterM() {
        // Regression: a non-SGR escape followed later by a literal 'm' must not
        // make the text between them be misread as SGR parameters and dropped.
        let (plain, _) = Ansi.parse("\u{1B}[Khi there minimum")
        XCTAssertEqual(plain, "hi there minimum")
    }

    func testSGRStillStylesText() {
        let (plain, runs) = Ansi.parse("\u{1B}[31mred\u{1B}[0m")
        XCTAssertEqual(plain, "red")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.foreground, .named("red"))
    }

    func testTruecolorSGRStillWorks() {
        let (plain, runs) = Ansi.parse("\u{1B}[38;2;10;20;30mx\u{1B}[0m")
        XCTAssertEqual(plain, "x")
        XCTAssertEqual(runs.first?.foreground, .rgb(r: 10, g: 20, b: 30, a: 255))
    }

    func testEraseBetweenStyledRunsKeepsStyle() {
        // A cursor/erase escape in the middle of a styled span leaves the SGR
        // state intact, so the whole visible text stays one run.
        let (plain, runs) = Ansi.parse("\u{1B}[31mab\u{1B}[Kcd\u{1B}[0m")
        XCTAssertEqual(plain, "abcd")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.range, 0..<4)
    }
}
