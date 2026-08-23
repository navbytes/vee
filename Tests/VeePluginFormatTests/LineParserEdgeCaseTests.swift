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

    // MARK: escape-boundary edge cases (review follow-up)

    /// Boundary: an escaped backslash (`\\`) immediately followed by a REAL,
    /// unescaped `|` — the escape pair must consume exactly its own two
    /// characters, leaving the very next `|` free to act as the delimiter.
    func testEscapedBackslashImmediatelyBeforeRealSeparator() {
        let (text, pairs, _) = LineParser.splitTextAndParams(#"text\\|key=value"#)
        XCTAssertEqual(text, #"text\"#)
        XCTAssertEqual(Dictionary(pairs, uniquingKeysWith: { a, _ in a })["key"], "value")
    }

    /// Boundary: two consecutive escape pairs (`\\` then `\|`) must each consume
    /// exactly their own two characters — no overlap, no dropped character.
    func testConsecutiveEscapedBackslashThenEscapedPipeInText() {
        let (text, pairs, _) = LineParser.splitTextAndParams(#"\\\|"#)
        XCTAssertEqual(text, #"\|"#)
        XCTAssertTrue(pairs.isEmpty)
    }

    /// Boundary: a trailing lone backslash (nothing left to pair with) must not
    /// crash and is kept exactly as written.
    func testTrailingLoneBackslashAtEndOfLineIsLiteral() {
        let (text, pairs, _) = LineParser.splitTextAndParams(#"trailing\"#)
        XCTAssertEqual(text, #"trailing\"#)
        XCTAssertTrue(pairs.isEmpty)
    }

    /// End-to-end: the exact line shape the bundled SDKs (plugins/typescript/vee.ts,
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

    // MARK: - sparkline size/colour (sparklinew=/sparklineh=/sparklinecolor=)

    /// The sparkline was the only inline accessory without size or colour
    /// knobs, while `progress=` and the chart shapes both had them. These
    /// assert it now takes the same vocabulary, including `full`.
    func testSparklineStyleParses() {
        let parsed = params("sparkline=1,2,3 sparklinew=140 sparklineh=18 sparklinecolor=teal")
        let style = parsed.swiftbar.sparklineStyle
        XCTAssertEqual(style?.width, 140)
        XCTAssertEqual(style?.height, 18)
        XCTAssertEqual(style?.color, .named("teal"))
        XCTAssertEqual(style?.isFullWidth, false)
    }

    func testSparklineFullWidthMirrorsProgressAndChart() {
        let style = params("sparkline=1,2,3 sparklinew=full").swiftbar.sparklineStyle
        XCTAssertEqual(style?.isFullWidth, true)
        XCTAssertNil(style?.width)
        // Falls back to the shared default rather than collapsing to zero.
        XCTAssertEqual(style?.effectiveWidth, SparklineStyle.defaultWidth)
        XCTAssertEqual(style?.effectiveHeight, SparklineStyle.defaultHeight)
    }

    /// A bare `sparkline=` carries no style at all, so the renderer keeps its
    /// own defaults instead of being handed an empty override.
    func testSparklineWithoutStyleLeavesStyleNil() {
        let parsed = params("sparkline=1,2,3")
        XCTAssertNil(parsed.swiftbar.sparklineStyle)
        XCTAssertEqual(parsed.sparkline, [1, 2, 3])
    }

    // MARK: - progresstrackcolor= and its deprecated spelling

    func testProgressTrackColorAcceptsBothSpellings() {
        let current = params("progress=0.5 progresstrackcolor=gray")
        let deprecated = params("progress=0.5 trackcolor=gray")
        XCTAssertEqual(current.progress?.trackColor, .named("gray"))
        XCTAssertEqual(deprecated.progress?.trackColor, .named("gray"),
                       "trackcolor= is the pre-v2 spelling and must keep working for published plugins")
        XCTAssertEqual(current.progress, deprecated.progress)
    }
}
