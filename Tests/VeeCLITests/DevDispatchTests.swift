import XCTest
import VeeRuntime
@testable import VeeCLI

/// Argument handling for `vee dev`, plus the non-TTY single-frame path. The test
/// process has no controlling terminal, so `VeeCLI.run` never enters the
/// interactive loop — which is exactly the guard being asserted.
final class DevDispatchTests: XCTestCase {
    private var dir = ""
    private var path = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "vee-dev-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        path = dir + "/cpu.10s.sh"
        try "#!/bin/bash\necho hi\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private final class FakeRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [ProcessInvocation] = []
        var calls: [ProcessInvocation] { lock.withLock { _calls } }
        var stdout = "CPU 12%\n---\nTop | href=https://example.com\n"
        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            lock.withLock { _calls.append(invocation) }
            return ProcessOutcome(standardOutput: stdout, standardError: "", exitCode: 0, timedOut: false)
        }
    }

    // MARK: - Non-TTY guard

    /// Raw mode and the alternate screen would corrupt a pipe, and with no
    /// keyboard nothing could ever ask the loop to quit — so a non-TTY prints
    /// one frame and returns instead of hanging forever.
    func testNonTTYPrintsOneFrameInsteadOfEnteringTheLoop() async {
        let fake = FakeRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["dev", path], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertTrue(out.contains("CPU 12%"), out)
        XCTAssertTrue(out.contains("cpu.10s.sh"), out)
        XCTAssertEqual(fake.calls.count, 1, "exactly one run, not a loop")
    }

    // MARK: - Argument errors

    func testMissingPathIsAUsageError() async {
        var out = "", err = ""
        let code = await VeeCLI.run(["dev"], runner: FakeRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("missing <path>"), err)
        XCTAssertTrue(err.contains("Usage: vee dev"), err)
    }

    func testUnknownFlagIsRejectedRatherThanIgnored() async {
        var out = "", err = ""
        let code = await VeeCLI.run(["dev", "--bogus", path], runner: FakeRunner(), out: &out, err: &err)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(err.contains("unknown flag"), err)
    }

    func testMissingFileIsReportedBeforeAnythingRuns() async {
        let fake = FakeRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["dev", dir + "/nope.sh"], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 1)
        XCTAssertTrue(err.contains("no such file"), err)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    // MARK: - Flags

    func testTextModeDoesNotExecute() async throws {
        let textPath = dir + "/menu.txt"
        try "Title\n---\nItem\n".write(toFile: textPath, atomically: true, encoding: .utf8)
        let fake = FakeRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["dev", "--text", textPath], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0, err)
        XCTAssertTrue(fake.calls.isEmpty, "--text must never spawn a process")
        XCTAssertTrue(out.contains("text (not executed)"), out)
        XCTAssertTrue(out.contains("Item"), out)
    }

    /// `--text` and `--push` are orthogonal: previewing hand-written protocol
    /// text in the menu bar is a normal thing to want.
    func testTextAndPushComposeAndDoNotExecuteTheFile() async throws {
        let textPath = dir + "/menu.txt"
        try "Title\n---\nItem\n".write(toFile: textPath, atomically: true, encoding: .utf8)
        let fake = FakeRunner()
        var out = "", err = ""
        let code = await VeeCLI.run(["dev", "--text", "--push", textPath], runner: fake, out: &out, err: &err)
        XCTAssertEqual(code, 0, err)

        let launched = fake.calls.map(\.launchPath)
        XCTAssertFalse(launched.contains(textPath), "--text must not execute the watched file")
        XCTAssertTrue(launched.contains("/usr/bin/open"), "--push must still send the preview: \(launched)")
    }

    func testNoPushFlagMeansNoProcessBeyondThePluginItself() async {
        let fake = FakeRunner()
        var out = "", err = ""
        _ = await VeeCLI.run(["dev", path], runner: fake, out: &out, err: &err)
        XCTAssertFalse(fake.calls.map(\.launchPath).contains("/usr/bin/open"),
                       "without --push the menu bar must be left alone")
    }

    /// A preview must never outlive the command that made it.
    func testPushIsTornDownOnTheSingleFramePath() async {
        let fake = FakeRunner()
        var out = "", err = ""
        _ = await VeeCLI.run(["dev", "--push", path], runner: fake, out: &out, err: &err)

        let opens = fake.calls.filter { $0.launchPath == "/usr/bin/open" }
        XCTAssertGreaterThanOrEqual(opens.count, 2, "expected a push and a teardown")
        XCTAssertTrue(opens.last?.arguments.last?.contains("exitafter=1") ?? false,
                      "the last open must be the teardown: \(opens.last?.arguments ?? [])")
    }

    func testDevAppearsInUsage() async {
        var out = "", err = ""
        _ = await VeeCLI.run(["--help"], runner: FakeRunner(), out: &out, err: &err)
        XCTAssertTrue(out.contains("vee dev <path>"), out)
        XCTAssertTrue(out.contains("--text"), out)
        XCTAssertTrue(out.contains("--push"), out)
        XCTAssertTrue(out.contains("--format"), out)
    }
}
