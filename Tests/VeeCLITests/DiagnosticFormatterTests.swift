import XCTest
@testable import VeeCLI
import VeePluginFormat

final class DiagnosticFormatterTests: XCTestCase {
    private func d(_ severity: ParseDiagnostic.Severity, _ message: String, line: Int? = nil) -> ParseDiagnostic {
        ParseDiagnostic(severity: severity, message: message, line: line)
    }

    // MARK: - Compact form

    func testCompactShapeForErrorAndWarning() {
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.error, "bare pipe in title text", line: 12), format: .compact, path: "menu.txt"),
            "menu.txt:12:1: error: bare pipe in title text")
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.warning, "unknown param 'colour'", line: 3), format: .compact, path: "menu.txt"),
            "menu.txt:3:1: warning: unknown param 'colour'")
    }

    /// An editor must never be handed a line number it cannot place. A finding
    /// with no line is still worth showing, so it lands on line 1 rather than
    /// being dropped or emitted as line 0 (which some editors reject).
    func testLinelessDiagnosticLandsOnLineOne() {
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.error, "no line known"), format: .compact, path: "menu.txt"),
            "menu.txt:1:1: error: no line known")
    }

    func testCompactUsesTheGivenPathVerbatim() {
        let stdout = DiagnosticFormatter.line(d(.error, "x", line: 2), format: .compact, path: DiagnosticFormatter.stdoutPseudoPath)
        XCTAssertEqual(stdout, "<stdout>:2:1: error: x")
        XCTAssertFalse(stdout.contains(".sh"), "script-mode findings must not name a source file")
    }

    // MARK: - Human form (must be unchanged)

    /// The default output is what Vee has always printed. Anyone who does not
    /// pass the flag must see byte-for-byte the same thing.
    func testHumanFormMatchesThePreviousOutputExactly() {
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.error, "bare pipe", line: 12), format: .human, path: "ignored.sh"),
            "  error [line 12]: bare pipe")
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.warning, "unknown param", line: 3), format: .human, path: "ignored.sh"),
            "  warning [line 3]: unknown param")
        XCTAssertEqual(
            DiagnosticFormatter.line(d(.error, "no line"), format: .human, path: "ignored.sh"),
            "  error: no line")
    }

    func testHumanFormIgnoresPath() {
        let withPath = DiagnosticFormatter.line(d(.error, "x", line: 1), format: .human, path: "some/file.sh")
        let withoutPath = DiagnosticFormatter.line(d(.error, "x", line: 1), format: .human, path: "")
        XCTAssertEqual(withPath, withoutPath)
    }

    // MARK: - render

    func testRenderEmitsOneNewlineTerminatedLinePerFinding() {
        let rendered = DiagnosticFormatter.render(
            [d(.error, "first", line: 1), d(.warning, "second", line: 2)],
            format: .compact,
            path: "a.txt")
        XCTAssertEqual(rendered, "a.txt:1:1: error: first\na.txt:2:1: warning: second\n")
    }

    func testEmptyInputProducesNoLines() {
        XCTAssertEqual(DiagnosticFormatter.render([], format: .compact, path: "a.txt"), "")
        XCTAssertEqual(DiagnosticFormatter.render([], format: .human, path: "a.txt"), "")
    }

    func testSortedOrdersByLineThenMessage() {
        let sorted = DiagnosticFormatter.sorted([
            d(.error, "zeta", line: 5),
            d(.error, "alpha", line: 5),
            d(.error, "later", line: 9),
            d(.error, "no line"),
        ])
        XCTAssertEqual(sorted.map(\.message), ["no line", "alpha", "zeta", "later"])
    }
}
