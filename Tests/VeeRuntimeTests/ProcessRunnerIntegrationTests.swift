import XCTest
import Darwin
import VeeCore
@testable import VeeRuntime

/// These spawn real subprocesses (fast, deterministic system binaries).
final class ProcessRunnerIntegrationTests: XCTestCase {
    private let runner = SystemProcessRunner()

    func testEchoStdout() async throws {
        let out = try await runner.run(ProcessInvocation(launchPath: "/bin/echo", arguments: ["hello world"]))
        XCTAssertEqual(out.standardOutput, "hello world\n")
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertFalse(out.timedOut)
    }

    func testExitCodeAndStderr() async throws {
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "echo oops 1>&2; exit 3"]
        ))
        XCTAssertEqual(out.exitCode, 3)
        XCTAssertEqual(out.standardError, "oops\n")
    }

    func testEnvironmentPassthrough() async throws {
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "echo $VEE_PLUGIN_PATH"],
            environment: ["VEE_PLUGIN_PATH": "/plugins/demo.sh", "PATH": "/usr/bin:/bin"]
        ))
        XCTAssertEqual(out.standardOutput, "/plugins/demo.sh\n")
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        // ~600 KB, far exceeding the pipe buffer — would hang without
        // incremental draining.
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "yes ABCDEFGH | head -n 75000"]
        ))
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertEqual(out.standardOutput.count, 75000 * 9) // "ABCDEFGH\n"
    }

    /// Regression: a plugin spewing far more than the capture cap must be
    /// truncated in memory (bounded-memory guarantee), not buffered wholesale —
    /// while still draining to EOF so the child never blocks.
    func testHugeOutputIsCappedNotUnbounded() async throws {
        // Emit ~12 MB, well past the 8 MB cap.
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "head -c 12582912 /dev/zero"],
            timeout: 30
        ))
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertFalse(out.timedOut)
        XCTAssertLessThanOrEqual(out.standardOutput.utf8.count, 8 * 1024 * 1024)
        XCTAssertGreaterThan(out.standardOutput.utf8.count, 4 * 1024 * 1024) // captured a lot, just bounded
    }

    func testTimeoutTerminatesProcess() async throws {
        let start = Date()
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sleep",
            arguments: ["10"],
            timeout: 0.3
        ))
        XCTAssertTrue(out.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0) // killed promptly
    }

    func testLaunchFailureThrows() async throws {
        do {
            _ = try await runner.run(ProcessInvocation(launchPath: "/nonexistent/binary-xyz"))
            XCTFail("expected launch failure")
        } catch let error as VeeError {
            guard case .launchFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    /// Leak proxy: many sequential spawns must not leak file descriptors
    /// (pipes/dispatch sources). A real `leaks`/Instruments run is the formal
    /// gate; this catches the common FD/pipe leak cheaply in CI.
    func testFileDescriptorsStableAcrossManyRuns() async throws {
        func openFDCount() -> Int {
            (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
        }
        // Warm up so lazily-created fds aren't counted as growth.
        for _ in 0..<10 { _ = try await runner.run(ProcessInvocation(launchPath: "/bin/echo", arguments: ["x"])) }
        let before = openFDCount()
        for _ in 0..<200 { _ = try await runner.run(ProcessInvocation(launchPath: "/bin/echo", arguments: ["x"])) }
        let after = openFDCount()
        XCTAssertLessThanOrEqual(after - before, 5, "fd count grew from \(before) to \(after) — likely a pipe/source leak")
    }

    /// Regression: a plugin that backgrounds a helper (`sleep 900 &`, a stray
    /// `curl`) used to leave it running forever after a timeout, because the
    /// old Foundation-`Process` runner only ever signaled the direct child.
    /// Every plugin is now spawned as the leader of its own process group, so
    /// a timeout's SIGTERM/SIGKILL reaches the whole group via `killpg`.
    func testTimeoutReapsBackgroundedGrandchildren() async throws {
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "sleep 300 & echo $!; sleep 300"],
            timeout: 0.5
        ))
        XCTAssertTrue(out.timedOut)

        let trimmed = out.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let grandchildPid = Int32(trimmed), grandchildPid > 0 else {
            return XCTFail("could not parse a positive grandchild pid from stdout: \(out.standardOutput)")
        }

        // Poll rather than sleep-and-check-once: the SIGKILL escalation is
        // 2s after the timeout, and CI scheduling can add its own delay.
        let deadline = Date().addingTimeInterval(8)
        var reaped = false
        while Date() < deadline {
            if kill(grandchildPid, 0) == -1, errno == ESRCH {
                reaped = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        if !reaped {
            // Courtesy cleanup: only ever the pid we parsed above (already
            // guarded > 0), only ever this one signal.
            kill(grandchildPid, SIGKILL)
            XCTFail("backgrounded grandchild pid \(grandchildPid) was still alive 8s after the timeout")
        }
    }

    /// `posix_spawn_file_actions_addchdir_np` must land the child in exactly
    /// the requested directory. Resolve symlinks on both sides — `/tmp` is
    /// itself a symlink to `/private/tmp` on macOS.
    func testWorkingDirectoryHonored() async throws {
        let dir = NSTemporaryDirectory() + "vee-proc-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "pwd"],
            workingDirectory: dir
        ))
        let reported = out.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = URL(fileURLWithPath: dir).resolvingSymlinksInPath().path
        let actual = URL(fileURLWithPath: reported).resolvingSymlinksInPath().path
        XCTAssertEqual(actual, expected)
    }

    /// `posix_spawn`/`execve` must still honor a `#!` shebang line when the
    /// script itself is the launch path — this is kernel exec behavior, not
    /// something Foundation's `Process` did for us, so it's worth locking in.
    func testShebangScriptRuns() async throws {
        let dir = NSTemporaryDirectory() + "vee-proc-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let scriptPath = dir + "/shebang-test.sh"
        try "#!/bin/sh\necho shebang-ok\n".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let out = try await runner.run(ProcessInvocation(launchPath: scriptPath))
        XCTAssertEqual(out.standardOutput, "shebang-ok\n")
        XCTAssertEqual(out.exitCode, 0)
    }

    /// Regression: a menu-bar app has no terminal to give a plugin, but
    /// Foundation's `Process` inherited whatever stdin Vee itself had. Stdin
    /// is now explicitly `/dev/null`, so a plugin that reads stdin (`cat`)
    /// sees immediate EOF instead of hanging until the timeout.
    func testStdinIsDevNull() async throws {
        let out = try await runner.run(ProcessInvocation(
            launchPath: "/bin/sh",
            arguments: ["-c", "cat; echo done"],
            timeout: 5
        ))
        XCTAssertEqual(out.standardOutput, "done\n")
        XCTAssertFalse(out.timedOut)
    }
}
