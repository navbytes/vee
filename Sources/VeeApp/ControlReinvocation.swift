import Foundation
import VeePluginFormat
import VeeRuntime

/// Builds the subprocess invocation that re-runs an interactive control item's
/// `shell=`/`bash=` command when the user commits a new value in the popover.
///
/// Kept pure (no AppKit, no process launching) so the value→command contract is
/// unit-testable in isolation. The chosen value reaches the plugin two ways so
/// authors can pick whichever is convenient:
///   • as the `VEE_CONTROL_VALUE` environment variable, and
///   • appended as the final positional argument.
/// Toggles pass `1`/`0`; sliders pass the numeric value (integers without a
/// trailing `.0`).
enum ControlReinvocation {
    static let valueEnvKey = "VEE_CONTROL_VALUE"

    /// Formats a control value the way a plugin sees it: integral values drop
    /// the `.0` (`5` not `5.0`) so shells and `case` statements match cleanly.
    static func format(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// Maps a `PluginControl` state to its committed numeric value.
    static func value(for control: PluginControl) -> Double {
        switch control {
        case .toggle(let on): return on ? 1 : 0
        case .slider(_, _, let value): return value
        }
    }

    /// Produces the invocation that re-runs `shell` carrying `value`.
    static func invocation(
        shell: ShellCommand,
        value: Double,
        baseEnvironment: [String: String]
    ) -> ProcessInvocation {
        let formatted = format(value)
        var environment = baseEnvironment
        environment[valueEnvKey] = formatted
        return ProcessInvocation(
            launchPath: shell.launchPath,
            arguments: shell.arguments + [formatted],
            environment: environment
        )
    }
}
