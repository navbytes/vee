import XCTest
@testable import VeeApp
import VeePluginFormat
import VeeRuntime

/// Covers the pure value→command contract used when an interactive
/// `toggle=`/`slider=` control commits a new value and re-invokes the plugin's
/// `shell=`/`bash=` command.
final class ControlReinvocationTests: XCTestCase {
    func testFormatDropsTrailingZeroForIntegralValues() {
        XCTAssertEqual(ControlReinvocation.format(5), "5")
        XCTAssertEqual(ControlReinvocation.format(0), "0")
        XCTAssertEqual(ControlReinvocation.format(-3), "-3")
    }

    func testFormatKeepsFractionalValues() {
        XCTAssertEqual(ControlReinvocation.format(0.25), "0.25")
        XCTAssertEqual(ControlReinvocation.format(-1.5), "-1.5")
    }

    func testValueForToggle() {
        XCTAssertEqual(ControlReinvocation.value(for: .toggle(on: true)), 1)
        XCTAssertEqual(ControlReinvocation.value(for: .toggle(on: false)), 0)
    }

    func testValueForSlider() {
        XCTAssertEqual(ControlReinvocation.value(for: .slider(min: 0, max: 10, value: 7)), 7)
    }

    func testInvocationAppendsValueAsTrailingArgAndEnv() {
        let shell = ShellCommand(launchPath: "/bin/plugin.sh", arguments: ["--set"], openInTerminal: false)
        let invocation = ControlReinvocation.invocation(
            shell: shell,
            value: 42,
            baseEnvironment: ["PATH": "/usr/bin"]
        )
        XCTAssertEqual(invocation.launchPath, "/bin/plugin.sh")
        XCTAssertEqual(invocation.arguments, ["--set", "42"])
        XCTAssertEqual(invocation.environment["PATH"], "/usr/bin")
        XCTAssertEqual(invocation.environment[ControlReinvocation.valueEnvKey], "42")
    }

    func testInvocationFormatsSliderValueInEnvAndArg() {
        let shell = ShellCommand(launchPath: "/bin/vol.sh", arguments: [], openInTerminal: false)
        let invocation = ControlReinvocation.invocation(
            shell: shell,
            value: 0.5,
            baseEnvironment: [:]
        )
        XCTAssertEqual(invocation.arguments, ["0.5"])
        XCTAssertEqual(invocation.environment[ControlReinvocation.valueEnvKey], "0.5")
    }
}
