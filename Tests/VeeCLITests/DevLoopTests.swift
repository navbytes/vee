import XCTest
import VeeRuntime
@testable import VeeCLI

/// `DevLoop.frame` is the whole visible surface of `vee dev`, and it is pure —
/// no TTY, no process, no clock — so every output shape is asserted directly.
final class DevLoopTests: XCTestCase {
    private func outcome(_ stdout: String, stderr: String = "", exit: Int32 = 0, timedOut: Bool = false) -> ProcessOutcome {
        ProcessOutcome(standardOutput: stdout, standardError: stderr, exitCode: exit, timedOut: timedOut)
    }

    private func snapshot(
        _ raw: String,
        mode: InputMode = .execute,
        stderr: String = "",
        exit: Int32 = 0,
        timedOut: Bool = false
    ) -> DevLoop.Snapshot {
        DevLoop.Snapshot(
            path: "/tmp/plugins/cpu.10s.sh",
            mode: mode,
            raw: raw,
            outcome: mode == .text ? nil : outcome(raw, stderr: stderr, exit: exit, timedOut: timedOut))
    }

    private func render(_ snapshot: DevLoop.Snapshot, extraNotes: [String] = []) -> String {
        DevLoop.frame(snapshot, width: 60, color: false, updatedAt: "12:00:00", extraNotes: extraNotes)
    }

    // MARK: - Sections

    func testCleanRunShowsNameStatusTreeAndFooter() {
        let frame = render(snapshot("CPU 12%\n---\nTop | href=https://example.com\n"))
        XCTAssertTrue(frame.contains("cpu.10s.sh"), frame)
        XCTAssertTrue(frame.contains("exit 0"), frame)
        XCTAssertTrue(frame.contains("CPU 12%"), frame)
        XCTAssertTrue(frame.contains("Top"), frame)
        XCTAssertTrue(frame.contains("updated 12:00:00"), frame)
        XCTAssertTrue(frame.contains("[r] re-run"), frame)
        XCTAssertTrue(frame.contains("[q] quit"), frame)
    }

    func testNonZeroExitIsReported() {
        let frame = render(snapshot("oops\n", exit: 3))
        XCTAssertTrue(frame.contains("exit 3"), frame)
        XCTAssertEqual(DevLoop.exitCode(for: snapshot("oops\n", exit: 3)), 1)
    }

    func testTimeoutIsReported() {
        let snap = snapshot("partial\n", timedOut: true)
        let frame = render(snap)
        XCTAssertTrue(frame.contains("timed out"), frame)
        XCTAssertEqual(DevLoop.exitCode(for: snap), 1)
    }

    func testStderrIsSurfaced() {
        let frame = render(snapshot("Title\n", stderr: "something went wrong\n"))
        XCTAssertTrue(frame.contains("stderr: something went wrong"), frame)
    }

    func testDiagnosticsAreSurfacedAlongsideTheTree() {
        let frame = render(snapshot("Title | colour=red\n"))
        XCTAssertTrue(frame.contains("Title"), "the best-effort tree must still render")
        XCTAssertTrue(frame.contains("unknown parameter 'colour'"), frame)
    }

    // MARK: - Text mode

    /// `--text` never ran anything, so reporting an exit code for it would be a
    /// fiction.
    func testTextModeReportsNotExecutedRatherThanAnExitCode() {
        let frame = render(snapshot("Title\n---\nItem\n", mode: .text))
        XCTAssertTrue(frame.contains("text (not executed)"), frame)
        XCTAssertFalse(frame.contains("exit "), frame)
        XCTAssertTrue(frame.contains("Item"), frame)
    }

    func testTextModeIsCleanWhenTheOutputIsFine() {
        XCTAssertEqual(DevLoop.exitCode(for: snapshot("Title\n", mode: .text)), 0)
    }

    // MARK: - Load failure

    /// A save that cannot even be loaded must repaint with the reason, because
    /// the loop keeps watching — exiting would end the session over a typo.
    func testLoadErrorIsShownInsteadOfATree() {
        let snap = DevLoop.Snapshot(path: "/tmp/gone.sh", mode: .execute, loadError: "could not run '/tmp/gone.sh': boom")
        let frame = render(snap)
        XCTAssertTrue(frame.contains("could not run"), frame)
        XCTAssertTrue(frame.contains("[q] quit"), "the footer must survive a failed load: \(frame)")
        XCTAssertEqual(DevLoop.exitCode(for: snap), 1)
    }

    // MARK: - Notes

    func testExtraNotesAppearInTheFrame() {
        let frame = render(snapshot("Title\n"), extraNotes: ["  preview skipped: menu is larger than 32 KB"])
        XCTAssertTrue(frame.contains("preview skipped"), frame)
    }

    // MARK: - Exit code

    func testCleanOutputHasAZeroExitCode() {
        XCTAssertEqual(DevLoop.exitCode(for: snapshot("Fine\n")), 0)
        XCTAssertEqual(DevLoop.exitCode(for: snapshot("Fine\n", mode: .text)), 0)
    }
}
