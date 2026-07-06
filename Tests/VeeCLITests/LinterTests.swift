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
}
