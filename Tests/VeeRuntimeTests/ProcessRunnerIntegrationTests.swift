import XCTest
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
}
