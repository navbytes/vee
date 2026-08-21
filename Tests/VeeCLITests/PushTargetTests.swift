import XCTest
import VeePluginFormat
import VeeRuntime
@testable import VeeCLI

/// `--push` sends a menu through a URL. Encoding it wrong would corrupt the very
/// characters a menu is made of — `|`, `&`, `#`, newlines — so the URL builder is
/// asserted directly, and the process calls are asserted through a fake runner.
final class PushTargetTests: XCTestCase {
    /// Records every invocation instead of running it.
    private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [ProcessInvocation] = []
        var calls: [ProcessInvocation] { lock.withLock { _calls } }
        /// Exit code keyed by launch path, so `pgrep` and `open` can be answered
        /// differently in one test.
        var exitCodes: [String: Int32] = [:]
        var stdouts: [String: String] = [:]

        func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
            lock.withLock { _calls.append(invocation) }
            return ProcessOutcome(
                standardOutput: stdouts[invocation.launchPath] ?? "",
                standardError: "",
                exitCode: exitCodes[invocation.launchPath] ?? 0,
                timedOut: false)
        }
    }

    private func snapshot(_ raw: String) -> DevLoop.Snapshot {
        DevLoop.Snapshot(
            path: "/tmp/plugins/cpu.10s.sh",
            mode: .execute,
            raw: raw,
            outcome: ProcessOutcome(standardOutput: raw, standardError: "", exitCode: 0, timedOut: false))
    }

    // MARK: - URL construction

    /// The characters a menu is actually made of must survive the round trip.
    func testEncodesTheCharactersAMenuIsMadeOf() throws {
        let content = "A&B | color=red\n---\nItem #1 | href=https://x.test/a?b=c+d\n"
        let urlString = try XCTUnwrap(PushTarget.url(key: "dev:cpu.10s.sh", content: content, exitAfter: 3600))

        // Three query parameters means exactly two '&' separators. Every '&'
        // from the content must be escaped rather than creating a third.
        XCTAssertEqual(urlString.filter { $0 == "&" }.count, 2, urlString)
        XCTAssertTrue(urlString.contains("%26"), "the content's own '&' must be escaped: \(urlString)")

        let components = try XCTUnwrap(URLComponents(string: urlString))
        let items = try XCTUnwrap(components.queryItems)
        let decoded = try XCTUnwrap(items.first { $0.name == "content" }?.value)
        XCTAssertEqual(decoded, content, "content must survive the round trip byte-for-byte")
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "dev:cpu.10s.sh")
        XCTAssertEqual(items.first { $0.name == "exitafter" }?.value, "3600")
    }

    func testNewlinesAndPipesSurviveTheRoundTrip() throws {
        let content = "Title | sfimage=cpu\n---\n-- Nested | color=#ff0000\n"
        let urlString = try XCTUnwrap(PushTarget.url(key: "k", content: content, exitAfter: nil))
        let components = try XCTUnwrap(URLComponents(string: urlString))
        XCTAssertEqual(components.queryItems?.first { $0.name == "content" }?.value, content)
        XCTAssertNil(components.queryItems?.first { $0.name == "exitafter" })
    }

    /// The key is what makes each save *update* one status item rather than
    /// accumulating one per save.
    func testKeyIsStableAcrossSaves() {
        XCTAssertEqual(PushTarget(path: "/a/b/cpu.10s.sh").key, PushTarget(path: "/a/b/cpu.10s.sh").key)
        XCTAssertEqual(PushTarget(path: "/somewhere/else/cpu.10s.sh").key, "dev:cpu.10s.sh")
        XCTAssertNotEqual(PushTarget(path: "/a/cpu.sh").key, PushTarget(path: "/a/ram.sh").key)
    }

    func testOversizedContentIsRefusedRatherThanTruncated() {
        let huge = String(repeating: "x", count: PushTarget.maxEncodedBytes + 1)
        XCTAssertNil(PushTarget.url(key: "k", content: huge, exitAfter: nil))
        XCTAssertNotNil(PushTarget.url(key: "k", content: String(repeating: "x", count: 100), exitAfter: nil))
    }

    // MARK: - Shell detection

    func testDetectsShellActionsAnywhereInTheTree() {
        func has(_ s: String) -> Bool { PushTarget.containsShellAction(OutputParser.parseAuto(s)) }
        XCTAssertTrue(has("Title | bash=/bin/echo\n"))
        XCTAssertTrue(has("Title\n---\nRun | shell=/bin/ls\n"))
        XCTAssertTrue(has("Title\n---\nParent\n-- Child | bash=/bin/danger\n"))
        XCTAssertTrue(has("Title\n---\nAlt | alternate=true shell=/bin/sneaky\n"))
        XCTAssertFalse(has("Title\n---\nOpen | href=https://example.com\n"))
    }

    // MARK: - Sending

    func testSendOpensTheUrlInTheBackground() async {
        let runner = RecordingRunner()
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        _ = await target.send(snapshot: snapshot("Title\n"), runner: runner, isFirstPush: false)

        let opens = runner.calls.filter { $0.launchPath == "/usr/bin/open" }
        XCTAssertEqual(opens.count, 1)
        XCTAssertEqual(opens.first?.arguments.first, "-g", "a dev command must never steal focus")
        XCTAssertTrue(opens.first?.arguments.last?.hasPrefix("vee://setephemeralplugin?") ?? false)
    }

    func testShellActionNoteIsShownOnceOnTheFirstPush() async {
        let runner = RecordingRunner()
        runner.stdouts["/usr/bin/pgrep"] = "123\n"     // Vee already running
        let target = PushTarget(path: "/tmp/cpu.10s.sh")

        let first = await target.send(snapshot: snapshot("Title\n---\nRun | bash=/bin/ls\n"), runner: runner, isFirstPush: true)
        XCTAssertTrue(first.contains { $0.contains("do not fire") }, "\(first)")

        let second = await target.send(snapshot: snapshot("Title\n---\nRun | bash=/bin/ls\n"), runner: runner, isFirstPush: false)
        XCTAssertFalse(second.contains { $0.contains("do not fire") }, "the note must not repeat on every save")
    }

    func testAnnouncesStartingVeeWhenItWasNotRunning() async {
        let runner = RecordingRunner()
        runner.exitCodes["/usr/bin/pgrep"] = 1         // not running
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        let notes = await target.send(snapshot: snapshot("Title\n"), runner: runner, isFirstPush: true)
        XCTAssertTrue(notes.contains { $0.contains("was not running") }, "\(notes)")
    }

    func testStaysQuietWhenVeeWasAlreadyRunning() async {
        let runner = RecordingRunner()
        runner.stdouts["/usr/bin/pgrep"] = "4242\n"
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        let notes = await target.send(snapshot: snapshot("Title\n"), runner: runner, isFirstPush: true)
        XCTAssertFalse(notes.contains { $0.contains("was not running") }, "\(notes)")
    }

    func testFailedOpenIsReportedAndDoesNotThrow() async {
        let runner = RecordingRunner()
        runner.exitCodes["/usr/bin/open"] = 1
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        let notes = await target.send(snapshot: snapshot("Title\n"), runner: runner, isFirstPush: false)
        XCTAssertTrue(notes.contains { $0.contains("could not be shown") }, "\(notes)")
    }

    func testOversizedMenuSkipsThePushWithAnExplanation() async {
        let runner = RecordingRunner()
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        let huge = String(repeating: "x", count: PushTarget.maxEncodedBytes + 10)
        let notes = await target.send(snapshot: snapshot(huge), runner: runner, isFirstPush: false)
        XCTAssertTrue(notes.contains { $0.contains("preview skipped") }, "\(notes)")
        XCTAssertTrue(runner.calls.filter { $0.launchPath == "/usr/bin/open" }.isEmpty)
    }

    func testNothingIsPushedWhenTheFileCouldNotBeLoaded() async {
        let runner = RecordingRunner()
        let target = PushTarget(path: "/tmp/cpu.10s.sh")
        let snap = DevLoop.Snapshot(path: "/tmp/cpu.10s.sh", mode: .execute, loadError: "boom")
        let notes = await target.send(snapshot: snap, runner: runner, isFirstPush: true)
        XCTAssertTrue(notes.isEmpty)
        XCTAssertTrue(runner.calls.isEmpty, "a failed load has no menu to preview")
    }

    // MARK: - Teardown

    func testTeardownExpiresThePreviewWithEmptyContent() async {
        let runner = RecordingRunner()
        await PushTarget(path: "/tmp/cpu.10s.sh").teardown(runner: runner)

        let url = try? XCTUnwrap(runner.calls.first { $0.launchPath == "/usr/bin/open" }?.arguments.last)
        let components = URLComponents(string: url ?? "")
        XCTAssertEqual(components?.queryItems?.first { $0.name == "exitafter" }?.value, "1")
        let content = components?.queryItems?.first { $0.name == "content" }?.value ?? "unset"
        XCTAssertTrue(content.isEmpty, "teardown must clear the item's content, got \(content)")
    }
}
