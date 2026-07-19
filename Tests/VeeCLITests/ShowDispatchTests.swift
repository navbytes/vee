import XCTest
import VeeRuntime
@testable import VeeCLI

/// End-to-end dispatch tests for `vee show`, driven through the same
/// buffer + injected-runner seam as the other subcommands. Every case uses
/// `--once` (and a non-TTY test process) so the single-frame path runs — the
/// interactive live loop is never entered.
final class ShowDispatchTests: XCTestCase {
    private var pluginPath = ""

    /// Writes a throwaway plugin file so `PluginResolver`'s existence check
    /// passes; the `FakeRunner` supplies the actual output, so the file's
    /// contents don't matter. Named `cpu.10s.sh` to exercise interval parsing.
    override func setUpWithError() throws {
        let dir = NSTemporaryDirectory() as NSString
        pluginPath = dir.appendingPathComponent("cpu.10s.sh")
        try "#!/bin/bash\necho hi\n".write(toFile: pluginPath, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: pluginPath)
    }

    private struct FakeRunner: ProcessRunning {
        var stdout: String
        var stderr: String = ""
        var exitCode: Int32 = 0
        var timedOut: Bool = false
        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            ProcessOutcome(standardOutput: stdout, standardError: stderr, exitCode: exitCode, timedOut: timedOut)
        }
    }

    func testShowOnceRendersTitleTreeAndStatus() async {
        let fake = FakeRunner(stdout: "CPU 12%\n---\nTop | href=https://example.com\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["show", pluginPath, "--once", "--no-color"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertTrue(out.contains("CPU 12%"), out)
        XCTAssertTrue(out.contains("Top"), out)
        XCTAssertTrue(out.contains("every 10s"), out)   // interval from filename
        XCTAssertTrue(out.contains("exit 0"), out)      // status line
    }

    func testShowOnceReflectsNonZeroExit() async {
        let fake = FakeRunner(stdout: "oops\n", exitCode: 3)
        var out = "", err = ""
        let code = await VeeCLI.run(["show", pluginPath, "--once", "--no-color"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("exit 3"), out)
    }

    func testShowOnceSurfacesDiagnostics() async {
        let fake = FakeRunner(stdout: "Item | bogus=1\n")
        var out = "", err = ""
        _ = await VeeCLI.run(["show", pluginPath, "--once", "--no-color"], runner: fake, out: &out, err: &err)
        XCTAssertTrue(out.contains("bogus"), out)   // parse diagnostic shown in the footer
    }

    func testShowMissingPluginArgExitsTwo() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["show", "--once"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("missing <plugin>"), err)
    }

    func testShowUnknownFileExitsOne() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["show", "/no/such/plugin.sh", "--once"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(err.contains("no such plugin file"), err)
    }

    func testShowUnknownFlagExitsTwo() async {
        let fake = FakeRunner(stdout: "")
        var out = "", err = ""
        let code = await VeeCLI.run(["show", pluginPath, "--bogus"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("unknown flag"), err)
    }

    func testShowIsRecognisedSubcommand() {
        XCTAssertEqual(
            ArgumentClassifier.classifyBare(["show", "cpu"]),
            .subcommand(name: "show", rest: ["cpu"]))
    }
}
