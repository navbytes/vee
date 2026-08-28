import XCTest
import VeePluginFormat
@testable import VeeCLI

final class LinterTests: XCTestCase {
    func testBarePipeInTitleTextProducesFinding() {
        // A title with a stray `|` in the text half (before the real separator).
        let raw = "CPU | 12% | color=green\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.contains { $0.message.contains("stray '|'") }, "\(findings)")
    }

    func testUnquotedSpaceValueProducesFinding() {
        // `tooltip=hello world` — the value `hello world` should have been quoted.
        let raw = "Item | tooltip=hello world\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.contains { $0.message.contains("isn't quoted") }, "\(findings)")
    }

    func testUnknownParamProducesFinding() {
        let raw = "Item | bogusparam=1\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.contains { $0.message.contains("unknown parameter 'bogusparam'") }, "\(findings)")
    }

    func testCleanOutputProducesNoFindings() {
        let raw = """
        CPU 12% | color=green sfimage=cpu
        ---
        Top processes | href=https://example.com
        Details | tooltip="load average"
        Refresh | refresh=true
        """
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    func testQuotedSpaceValueIsClean() {
        let raw = "Item | tooltip=\"hello world\"\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertFalse(findings.contains { $0.message.contains("isn't quoted") }, "\(findings)")
    }

    func testKnownParamsIncludingPositionalAreClean() {
        let raw = "Run | bash=/bin/echo param1=hi param2=there refresh=true\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    /// Regression: `header=`/`accessory=` are valid Vee-native params (see
    /// `LineParser`'s `header`/`accessory` cases) that `vee render` already
    /// accepted, but `knownParams` hadn't caught up — a plugin line using both
    /// used to false-positive as "unknown parameter".
    func testHeaderAndAccessoryParamsAreKnown() {
        let raw = "Budget | header=false accessory=leading\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }

    /// The chart params (`pie=`/`donut=`/`stackedbar=` and their positional
    /// `chartlabels=`/`chartcolors=`) are known to the linter, so a valid chart
    /// line doesn't false-positive as "unknown parameter".
    func testChartParamsAreKnown() {
        let raw = "Disk | pie=45,30,25 chartlabels=Docs,Photos,Apps chartcolors=red,,blue\n"
        XCTAssertTrue(Linter.lint(rawOutput: raw).isEmpty, "\(Linter.lint(rawOutput: raw))")
    }

    /// Regression: a Windows-line-ending plugin's `---\r` must still be
    /// recognized as the title/body separator (`.whitespaces` trimming
    /// doesn't strip "\r"). Before the fix, `inBody` stayed permanently
    /// false, so this body line's second top-level `|` — harmless below the
    /// separator, since both `tooltip` and `bash` are well-formed — was
    /// wrongly linted as a "stray '|' in title text", a check that's only
    /// meant to apply above the separator.
    func testCRLFSeparatorIsRecognized() {
        let raw = "Title\r\n---\r\nWeird | tooltip=\"hi\" | bash=/bin/echo\r\n"
        let findings = Linter.lint(rawOutput: raw)
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }
    /// The bundled SDKs escape `|` as `\|` when serializing user text, and
    /// `LineParser.splitTextAndParams` unescapes it correctly. The linter used
    /// to re-tokenize with its own rule that had no escape handling, so it
    /// warned about a stray pipe in output Vee itself produces.
    func testEscapedPipeInTitleTextIsNotAStrayPipe() {
        let diags = Linter.lint(rawOutput: "Total: 5 \\| 3 | color=red\n")
        XCTAssertTrue(diags.filter { $0.message.contains("stray") }.isEmpty,
                      "an escaped pipe is display text, not a separator: \(diags.map(\.message))")
    }

    /// The warning must still fire for a genuinely unescaped second pipe —
    /// the case it exists for.
    func testUnescapedSecondPipeIsStillFlagged() {
        let diags = Linter.lint(rawOutput: "Total: 5 | 3 | color=red\n")
        XCTAssertFalse(diags.filter { $0.message.contains("stray") }.isEmpty,
                       "a bare second pipe really is mis-parsed and must warn")
    }

    /// The escape also must not shift where params begin: everything after the
    /// first UNESCAPED pipe is still the parameter half.
    func testEscapedPipeDoesNotHideParameterDiagnostics() {
        let diags = Linter.lint(rawOutput: "A \\| B | colour=red\n")
        XCTAssertFalse(diags.filter { $0.message.contains("colour") }.isEmpty,
                       "the unknown key after the real separator must still be found: \(diags.map(\.message))")
    }

}
