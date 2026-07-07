import XCTest
import VeeRuntime
@testable import VeeCLI

/// A canned `ProcessRunning` that returns a fixed outcome for `render`/`lint`
/// so dispatch is testable without spawning a process.
private struct FakeRunner: ProcessRunning {
    var stdout: String
    var stderr: String = ""
    var exitCode: Int32 = 0
    var timedOut: Bool = false

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
        ProcessOutcome(standardOutput: stdout, standardError: stderr, exitCode: exitCode, timedOut: timedOut)
    }
}

final class DispatchTests: XCTestCase {
    func testRenderDrivesTreeFromCannedStdout() async {
        let fake = FakeRunner(stdout: "CPU 12%\n---\nTop | href=https://example.com\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["render", "/tmp/plugin.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("CPU 12%"), out)
        XCTAssertTrue(out.contains("href=https://example.com"), out)
    }

    func testRenderReportsNonzeroChildExit() async {
        let fake = FakeRunner(stdout: "Hi\n", exitCode: 3)
        var out = "", err = ""
        let code = await VeeCLI.run(["render", "/tmp/plugin.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(err.contains("exited with code 3"), err)
    }

    func testLintFlagsUnknownParamFromCannedStdout() async {
        let fake = FakeRunner(stdout: "Item | bogus=1\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "/tmp/plugin.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("bogus"), out)
    }

    /// Regression: an unknown param is flagged by both the parser and the raw
    /// linter — the merged output must report it exactly once (with its line).
    func testLintDoesNotDuplicateUnknownParam() async {
        let fake = FakeRunner(stdout: "Item | frobnicate=yes\n")
        var out = "", err = ""
        _ = await VeeCLI.run(["lint", "/tmp/plugin.sh"], runner: fake, out: &out, err: &err)
        let occurrences = out.components(separatedBy: "unknown parameter 'frobnicate'").count - 1
        XCTAssertEqual(occurrences, 1, "expected a single unknown-param finding, got:\n\(out)")
    }

    func testLintCleanOutputExitsZero() async {
        let fake = FakeRunner(stdout: "CPU | color=green\n---\nRefresh | refresh=true\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "/tmp/plugin.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("No lint findings"), out)
    }

    // MARK: - search

    func testSearchFiltersFlattenedNestedItems() async {
        let fake = FakeRunner(stdout: "Title\n---\nParent\n--Open Issue | href=https://x\n--Close Issue | href=https://y\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["search", "/tmp/p.sh", "open"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("Open Issue"), out)
        XCTAssertFalse(out.contains("Close Issue"), out)
        XCTAssertTrue(out.contains("Parent"), out)          // breadcrumb rendered
        XCTAssertTrue(out.contains("[href]"), out)          // action label rendered
    }

    func testSearchNoQueryListsAllActivatableItems() async {
        let fake = FakeRunner(stdout: "Title\n---\nInfo line\nGo | href=https://x\nRefresh | refresh=true\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["search", "/tmp/p.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("2 activatable item(s)"), out)  // "Info line" is not activatable
        XCTAssertFalse(out.contains("Info line"), out)
    }

    func testSearchNoMatchExitsOne() async {
        let fake = FakeRunner(stdout: "Title\n---\nGo | href=https://x\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["search", "/tmp/p.sh", "zzzz"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("(no matches)"), out)
    }

    func testSearchMissingPathExitsTwo() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["search"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("missing <path>"), err)
    }

    func testUnknownSubcommandExitsTwo() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["bogus"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 2)
    }

    func testNewPrintsScaffoldToStdout() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["new", "--lang", "sh", "--interval", "5s", "--name", "Demo"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("demo.5s.sh"), out)
        XCTAssertTrue(out.contains("<xbar.title>Demo</xbar.title>"), out)
    }

    // MARK: - Argument classification (the app-boot guarantee)

    func testEmptyArgsAreNoSubcommand() {
        XCTAssertEqual(ArgumentClassifier.classifyBare([]), .none)
    }

    func testProcessSerialNumberArgIsNoSubcommand() {
        // LaunchServices passes `-psn_0_123` on double-launch: must NOT be read
        // as a CLI subcommand, so the app still boots.
        XCTAssertEqual(ArgumentClassifier.classifyBare(["-psn_0_123"]), .none)
    }

    func testLeadingFlagIsNoSubcommand() {
        XCTAssertEqual(ArgumentClassifier.classifyBare(["--some-app-flag"]), .none)
    }

    func testRenderIsRecognisedSubcommand() {
        XCTAssertEqual(
            ArgumentClassifier.classifyBare(["render", "/a/b.sh"]),
            .subcommand(name: "render", rest: ["/a/b.sh"]))
    }

    func testHelpIsTopLevelFlag() {
        XCTAssertEqual(ArgumentClassifier.classifyBare(["--help"]), .topLevelFlag("--help"))
        XCTAssertEqual(ArgumentClassifier.classifyBare(["-h"]), .topLevelFlag("-h"))
    }

    func testClassifyIncludesExecutableName() {
        // `classify` drops argv[0]; a bare exec name → no subcommand (app boot).
        XCTAssertEqual(ArgumentClassifier.classify(["/path/to/vee"]), .none)
        XCTAssertEqual(
            ArgumentClassifier.classify(["/path/to/vee", "render", "x"]),
            .subcommand(name: "render", rest: ["x"]))
    }
}
