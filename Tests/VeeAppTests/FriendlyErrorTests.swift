import XCTest
import VeeRuntime
@testable import VeeApp

@MainActor
final class FriendlyErrorTests: XCTestCase {
    func testDetectsCommandNotFound() {
        XCTAssertEqual(PluginCoordinator.missingCommand(inStderr: "jq: command not found"), "jq")
    }

    func testDetectsNoSuchFile() {
        XCTAssertEqual(PluginCoordinator.missingCommand(inStderr: "/usr/local/bin/jq: No such file or directory"), "jq")
    }

    func testNoMatch() {
        XCTAssertNil(PluginCoordinator.missingCommand(inStderr: "some other error"))
    }

    func testFriendlyMessageForMissingCommand() {
        let outcome = ProcessOutcome(standardOutput: "", standardError: "jq: command not found\n", exitCode: 127, timedOut: false)
        XCTAssertTrue(PluginCoordinator.friendlyError(outcome).contains("jq"))
    }
}
