import Foundation
import XCTest
@testable import VeePluginFormat

/// Edge cases in the `key=value` parameter parser and its mapping onto
/// `LineParams` — the kinds of malformed/hostile plugin output that must not
/// crash or silently lose data.
final class LineParserEdgeCaseTests: XCTestCase {
    private func params(_ s: String) -> LineParams {
        LineParser.mapParams(LineParser.parseParams(s).pairs).params
    }

    private func mapped(_ s: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        LineParser.mapParams(LineParser.parseParams(s).pairs)
    }

    // MARK: length

    /// A negative `length=` must never reach `String.prefix(_:)` (which traps on
    /// a negative argument and crashes the whole menu-bar app). Clamp at parse.
    func testNegativeLengthClampsToZero() {
        XCTAssertEqual(params("length=-1").length, 0)
        XCTAssertEqual(params("length=-999").length, 0)
    }

    func testZeroAndPositiveLengthPreserved() {
        XCTAssertEqual(params("length=0").length, 0)
        XCTAssertEqual(params("length=5").length, 5)
    }

    func testNonNumericLengthIsNil() {
        XCTAssertNil(params("length=abc").length)
    }

    // MARK: tab-separated params

    /// A tab between a bare value and the next key must terminate the value —
    /// otherwise the tab and everything after it is swallowed into the value and
    /// the following params are lost.
    func testTabTerminatesBareValue() {
        let parsed = LineParser.parseParams("color=red\tsize=14")
        let dict = Dictionary(parsed.pairs, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["color"], "red")
        XCTAssertEqual(dict["size"], "14")
    }

    func testSpaceStillSeparatesParams() {
        let parsed = LineParser.parseParams("color=red size=14")
        let dict = Dictionary(parsed.pairs, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["color"], "red")
        XCTAssertEqual(dict["size"], "14")
    }

    // MARK: `\|`/`\n`/`\\` escaping (fix 2)

    /// A literal `|` in display text must not be read as the text/params
    /// delimiter — the bundled SDKs escape it as `\|` for exactly this reason.
    func testEscapedPipeInTextIsNotTreatedAsDelimiter() {
        // The space right before the real (unescaped) delimiter `|` is part of
        // the untrimmed text, same as any other `text | params` line — trimming
        // is a separate, later step (`trim=`, default on).
        let (text, pairs, _) = LineParser.splitTextAndParams(#"A\|B | color=red"#)
        XCTAssertEqual(text, "A|B ")
        XCTAssertEqual(Dictionary(pairs, uniquingKeysWith: { a, _ in a })["color"], "red")
    }

    /// `\n` in display text unescapes to a real newline. The SDKs use this to
    /// keep an embedded newline on one stdout line — a raw newline byte would
    /// otherwise be read by `OutputParser` as a separate (corrupted) line.
    func testEscapedNewlineInTextUnescapesToRealNewline() {
        let (text, _, _) = LineParser.splitTextAndParams(#"Line1\nLine2"#)
        XCTAssertEqual(text, "Line1\nLine2")
    }

    func testEscapedBackslashInTextUnescapesToSingleBackslash() {
        let (text, _, _) = LineParser.splitTextAndParams(#"C:\\Users"#)
        XCTAssertEqual(text, #"C:\Users"#)
    }

    /// An unrecognized backslash sequence (anything but `\|`/`\n`/`\\`) is left
    /// exactly as written — permissive, so output that already prints a literal
    /// `\` followed by an unrelated character (e.g. a Windows path) is unaffected.
    func testUnrecognizedBackslashSequenceIsLeftLiteral() {
        let (text, _, _) = LineParser.splitTextAndParams(#"C:\Users"#)
        XCTAssertEqual(text, #"C:\Users"#)
    }

    /// The same three escapes apply inside a quoted param value, identically.
    func testQuotedParamValueUnescapesPipeNewlineAndBackslash() {
        let (pairs, _) = LineParser.parseParams(#"tooltip="a\|b\nc\\d""#)
        XCTAssertEqual(pairs.first?.value, "a|b\nc\\d")
    }

    /// End-to-end: the exact line shape the bundled SDKs (plugins/src/vee.ts,
    /// plugins/python/vee.py, plugins/go/vee.go) emit for an item whose text is
    /// `Left | Right<newline>Second line` round-trips through the full parser
    /// back to the original text.
    func testEscapedPipeAndNewlineRoundTripsThroughOutputParser() {
        let escapedLine = #"Left \| Right\nSecond line | color=red"#
        let out = OutputParser.parse("Title\n---\n\(escapedLine)")
        let item = out.body.items[0]
        XCTAssertEqual(item.text, "Left | Right\nSecond line")
        XCTAssertEqual(item.params.color, .named("red"))
    }

    // MARK: silent-drop diagnostics (fix 3)

    func testUnsafeHrefSchemeEmitsDiagnosticAndDrops() {
        for hostile in ["file:///etc/passwd", "javascript:alert(1)"] {
            let (p, diags) = mapped("href=\(hostile)")
            XCTAssertNil(p.href, hostile)
            XCTAssertTrue(diags.contains { $0.message.contains("missing or unsafe url") }, hostile)
        }
    }

    func testSafeHrefEmitsNoDiagnostic() {
        let (p, diags) = mapped("href=https://example.com")
        XCTAssertEqual(p.href, URL(string: "https://example.com"))
        XCTAssertTrue(diags.isEmpty)
    }

    func testDuplicateParameterEmitsDiagnostic() {
        let (p, diags) = mapped("color=red color=blue")
        XCTAssertEqual(p.color, .named("blue"), "last one wins, unchanged")
        XCTAssertTrue(diags.contains { $0.message == "duplicate parameter 'color'" })
    }

    func testDistinctParametersEmitNoDuplicateDiagnostic() {
        let (_, diags) = mapped("color=red size=14")
        XCTAssertFalse(diags.contains { $0.message.contains("duplicate parameter") })
    }

    func testInvalidBase64ImageEmitsDiagnosticAndDrops() {
        let (p, diags) = mapped("image=abc")
        XCTAssertNil(p.image)
        XCTAssertTrue(diags.contains { $0.message.contains("image= is not valid base64") })
    }

    func testOversizedBase64TemplateImageEmitsDiagnosticAndDrops() {
        let huge = Data(repeating: 0, count: 3_000_000).base64EncodedString()
        let (p, diags) = mapped("templateimage=\(huge)")
        XCTAssertNil(p.templateImage)
        XCTAssertTrue(diags.contains { $0.message.contains("templateImage= decodes to over") })
    }

    func testValidBase64ImageIsKeptWithNoDiagnostic() {
        let small = Data([0xFF, 0xD8, 0xFF]).base64EncodedString()
        let (p, diags) = mapped("image=\(small)")
        XCTAssertEqual(p.image, small)
        XCTAssertTrue(diags.isEmpty)
    }
}
