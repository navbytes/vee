import XCTest
import VeeRuntime
@testable import VeeCLI

/// `--text` and `--format` on `vee lint`. The important property is not the
/// convenience of not executing — it is that the mode decides what file a
/// compact finding is allowed to name.
final class TextModeDispatchTests: XCTestCase {
    private var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "vee-textmode-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    @discardableResult
    private func write(_ name: String, _ contents: String, executable: Bool = false) throws -> String {
        let path = dir + "/" + name
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        return path
    }

    /// Records whether it was ever asked to run anything.
    private final class SpyRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _runCount = 0
        var runCount: Int { lock.lock(); defer { lock.unlock() }; return _runCount }
        var stdout: String = ""
        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            // `withLock` rather than `lock()`/`unlock()`: the latter is
            // unavailable from an async context.
            lock.withLock { _runCount += 1 }
            return ProcessOutcome(standardOutput: stdout, standardError: "", exitCode: 0, timedOut: false)
        }
    }

    // MARK: - --text does not execute

    func testTextModeDoesNotExecuteTheFile() async throws {
        let path = try write("menu.txt", "Title | colour=red\n")
        let spy = SpyRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", path], runner: spy, out: &out, err: &err)
        XCTAssertEqual(code, 1, "the unknown param should be a finding")
        XCTAssertEqual(spy.runCount, 0, "--text must never spawn a process for the watched file")
        XCTAssertTrue(out.contains("colour"), out)
    }

    /// The whole point of the mode: a plain text file with no execute bit and no
    /// shebang is a valid input.
    func testTextModeWorksOnANonExecutableFileWithNoShebang() async throws {
        let path = try write("menu.txt", "All good\n---\nOpen | href=https://example.com\n")
        let spy = SpyRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", path], runner: spy, out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertEqual(spy.runCount, 0)
        XCTAssertTrue(out.contains("No lint findings"), out)
    }

    func testExecuteModeStillRunsTheFile() async throws {
        let path = try write("gen.sh", "#!/bin/bash\necho hi\n", executable: true)
        let spy = SpyRunner()
        spy.stdout = "Title | colour=red\n"
        var out = "", err = ""
        _ = await VeeCLI.run(["lint", path], runner: spy, out: &out, err: &err)
        XCTAssertEqual(spy.runCount, 1, "without --text the plugin must still be executed")
    }

    // MARK: - Path attribution

    func testCompactNamesTheRealPathUnderText() async throws {
        let path = try write("menu.txt", "Title | colour=red\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", "--format", "compact", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("\(path):1:1: warning:"), out)
    }

    /// Script-mode findings index stdout, so naming the script would put
    /// squiggles on lines that are not wrong.
    func testCompactNamesStdoutPseudoPathWithoutText() async throws {
        let path = try write("gen.sh", "#!/bin/bash\n", executable: true)
        let spy = SpyRunner()
        spy.stdout = "Title | colour=red\n"
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--format", "compact", path], runner: spy, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(out.contains("<stdout>:1:1: warning:"), out)
        XCTAssertFalse(out.contains(path), "an executed script must never be named by a compact finding")
    }

    // MARK: - Output shape

    /// An editor parses this stream; prose lines in it would be parsed as junk.
    func testCompactEmitsFindingsOnlyWithNoProseHeaderOrFooter() async throws {
        let path = try write("menu.txt", "Title | colour=red\n")
        var out = "", err = ""
        _ = await VeeCLI.run(["lint", "--text", "--format", "compact", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertFalse(out.contains("Lint findings"), out)
        for line in out.split(separator: "\n") {
            XCTAssertTrue(line.contains(":1: warning:") || line.contains(":1: error:"), "unexpected prose line: \(line)")
        }
    }

    func testCompactWithNoFindingsEmitsNothing() async throws {
        let path = try write("menu.txt", "All good\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", "--format", "compact", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertEqual(out, "", "a clean file must produce no output for an editor to parse")
    }

    /// Anyone who does not pass the flag must see exactly what they saw before.
    func testHumanFormRemainsTheDefault() async throws {
        let path = try write("menu.txt", "Title | colour=red\n")
        var out = "", err = ""
        _ = await VeeCLI.run(["lint", "--text", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertTrue(out.hasPrefix("Lint findings:\n"), out)
        XCTAssertTrue(out.contains("  warning [line 1]: unknown parameter 'colour'"), out)
    }

    // MARK: - Argument errors

    func testUnknownFormatIsAUsageError() async throws {
        let path = try write("menu.txt", "x\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", "--format", "bogus", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("--format"), err)
    }

    func testUnknownFlagIsRejectedRatherThanIgnored() async throws {
        let path = try write("menu.txt", "x\n")
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--nope", path], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("unknown flag"), err)
    }

    func testMissingPathIsAUsageError() async {
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text"], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("missing <path>"), err)
    }

    func testUnreadableFileInTextModeReportsReadNotRun() async {
        var out = "", err = ""
        let code = await VeeCLI.run(["lint", "--text", dir + "/nope.txt"], runner: SpyRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(err.contains("could not read"), err)
    }
}
