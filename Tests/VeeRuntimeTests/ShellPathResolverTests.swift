import XCTest
import VeeCore
@testable import VeeRuntime

final class ShellPathResolverTests: XCTestCase {
    func testAugmentAppendsMissingKnownDirs() {
        let exists: (String) -> Bool = { $0 == "/opt/homebrew/bin" || $0 == "/home/me/.local/bin" }
        let result = ShellPathResolver.augment("/usr/bin:/bin", home: "/home/me", fileExists: exists)
        // Existing entries stay first, in order.
        XCTAssertTrue(result.hasPrefix("/usr/bin:/bin"))
        // Only the known dirs that "exist" are appended.
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result.contains("/home/me/.local/bin"))
        XCTAssertFalse(result.contains("/usr/local/bin"))
    }

    func testAugmentDeduplicatesAndSkipsEmpty() {
        let exists: (String) -> Bool = { $0 == "/opt/homebrew/bin" }
        // "/opt/homebrew/bin" already present; a trailing empty segment is ignored.
        let result = ShellPathResolver.augment("/opt/homebrew/bin:/usr/bin:", home: nil, fileExists: exists)
        XCTAssertEqual(result, "/opt/homebrew/bin:/usr/bin")
    }

    func testResolvePathUsesShellOutput() async {
        let runner = RecordingProcessRunner(stub: ProcessOutcome(
            standardOutput: "/custom/bin:/usr/bin\n", standardError: "", exitCode: 0, timedOut: false))
        let path = await ShellPathResolver.resolvePath(
            shell: "/bin/zsh", runner: runner, base: ["HOME": "/home/me"], current: "/usr/bin:/bin")
        XCTAssertTrue(path.hasPrefix("/custom/bin:/usr/bin"))
        let invocation = await runner.lastInvocation
        XCTAssertEqual(invocation?.launchPath, "/bin/zsh")
        XCTAssertEqual(invocation?.arguments, ["-ilc", "printf %s \"$PATH\""])
    }

    func testResolvePathFallsBackOnFailure() async {
        let runner = RecordingProcessRunner(stub: ProcessOutcome(
            standardOutput: "", standardError: "boom", exitCode: 1, timedOut: false))
        let path = await ShellPathResolver.resolvePath(
            shell: "/bin/zsh", runner: runner, base: [:], current: "/usr/bin:/bin")
        XCTAssertTrue(path.hasPrefix("/usr/bin:/bin"))
    }

    func testResolvedEnvironmentReplacesPath() async {
        let runner = RecordingProcessRunner(stub: ProcessOutcome(
            standardOutput: "/custom/bin", standardError: "", exitCode: 0, timedOut: false))
        let env = await ShellPathResolver.resolvedEnvironment(
            runner: runner, base: ["SHELL": "/bin/bash", "PATH": "/usr/bin", "FOO": "bar"])
        XCTAssertTrue(env["PATH"]?.hasPrefix("/custom/bin") ?? false)
        XCTAssertEqual(env["FOO"], "bar")  // other vars preserved
    }
}
