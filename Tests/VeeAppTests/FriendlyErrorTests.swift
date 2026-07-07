import XCTest
import VeeRuntime
@testable import VeeApp

@MainActor
final class FriendlyErrorTests: XCTestCase {
    func testDetectsCommandNotFound() {
        XCTAssertEqual(PluginCoordinator.missingCommand(inStderr: "jq: command not found"), "jq")
    }

    /// Real bash prefixes the failing line with the script path and line number;
    /// the command is the field immediately before "command not found", not the
    /// first colon-field (which is the script path).
    func testDetectsCommandNotFoundInRealBashOutput() {
        XCTAssertEqual(
            PluginCoordinator.missingCommand(inStderr: "/Users/x/plugins/cpu.5s.sh: line 3: jq: command not found"),
            "jq"
        )
    }

    func testDetectsNoSuchFile() {
        XCTAssertEqual(PluginCoordinator.missingCommand(inStderr: "/usr/local/bin/jq: No such file or directory"), "jq")
    }

    func testDetectsNoSuchFileInRealBashOutput() {
        XCTAssertEqual(
            PluginCoordinator.missingCommand(inStderr: "/Users/x/plugins/foo.1m.sh: line 2: /opt/bin/tool: No such file or directory"),
            "tool"
        )
    }

    func testNoMatch() {
        XCTAssertNil(PluginCoordinator.missingCommand(inStderr: "some other error"))
    }

    func testFriendlyMessageForMissingCommand() {
        let outcome = ProcessOutcome(standardOutput: "", standardError: "jq: command not found\n", exitCode: 127, timedOut: false)
        XCTAssertTrue(PluginCoordinator.friendlyError(outcome).contains("jq"))
    }
}
