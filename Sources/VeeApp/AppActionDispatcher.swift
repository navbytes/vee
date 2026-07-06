import AppKit
import VeePluginFormat
import VeeRuntime
import VeeMenu

/// Handles menu-item activation for one plugin: open URLs, run shell actions
/// (in Terminal or detached), and trigger refreshes.
@MainActor
final class AppActionDispatcher: MenuActionHandling {
    private let runner: ProcessRunning
    private let baseEnvironment: [String: String]
    private let onRefresh: () -> Void

    init(runner: ProcessRunning, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment, onRefresh: @escaping () -> Void) {
        self.runner = runner
        self.baseEnvironment = baseEnvironment
        self.onRefresh = onRefresh
    }

    func perform(_ item: MenuItem) {
        let params = item.params
        // A control item also carries `shell=` (to re-invoke on change), so it
        // must be handled before the plain `shell` branch — otherwise clicking
        // it would fire the command immediately instead of opening the popover.
        if let control = params.control {
            presentControl(control, item: item)
        } else if let shell = params.shell {
            if shell.openInTerminal {
                runInTerminal(shell)
            } else {
                runDetached(shell, refreshAfter: params.refresh == true)
            }
        } else if let webview = params.swiftbar.webview {
            WebViewPresenter.shared.show(url: webview, width: params.swiftbar.webviewWidth, height: params.swiftbar.webviewHeight)
        } else if let series = params.sparkline {
            PluginPopover.shared.show(series: series, title: item.text)
        } else if let url = params.href {
            NSWorkspace.shared.open(url)
        } else if let shortcut = params.swiftbar.shortcut, !shortcut.isEmpty {
            runShortcut(named: shortcut, refreshAfter: params.refresh == true)
        } else if params.refresh == true {
            onRefresh()
        }
    }

    /// Opens the interactive control popover for `item`. When the user commits
    /// a value, re-invokes the item's `shell=`/`bash=` command carrying that
    /// value (`VEE_CONTROL_VALUE` + trailing arg), then refreshes if requested.
    /// A control with no `shell` still shows — it just has nothing to re-invoke.
    private func presentControl(_ control: PluginControl, item: MenuItem) {
        let shell = item.params.shell
        let refreshAfter = item.params.refresh == true
        PluginPopover.shared.show(control: control, title: item.text) { [weak self] value in
            guard let self, let shell else { return }
            let invocation = ControlReinvocation.invocation(
                shell: shell,
                value: value,
                baseEnvironment: self.baseEnvironment
            )
            let runner = self.runner
            let onRefresh = self.onRefresh
            Task {
                _ = try? await runner.run(invocation)
                if refreshAfter {
                    await MainActor.run { onRefresh() }
                }
            }
        }
    }

    /// Runs a macOS Shortcut by name via the `shortcuts` CLI (`shortcut=` param).
    private func runShortcut(named name: String, refreshAfter: Bool) {
        let invocation = ProcessInvocation(
            launchPath: "/usr/bin/shortcuts",
            arguments: ["run", name],
            environment: baseEnvironment
        )
        let runner = self.runner
        let onRefresh = self.onRefresh
        Task {
            _ = try? await runner.run(invocation)
            if refreshAfter {
                await MainActor.run { onRefresh() }
            }
        }
    }

    private func runDetached(_ shell: ShellCommand, refreshAfter: Bool) {
        let invocation = ProcessInvocation(
            launchPath: shell.launchPath,
            arguments: shell.arguments,
            environment: baseEnvironment
        )
        let runner = self.runner
        let onRefresh = self.onRefresh
        Task {
            _ = try? await runner.run(invocation)
            if refreshAfter {
                await MainActor.run { onRefresh() }
            }
        }
    }

    private func runInTerminal(_ shell: ShellCommand) {
        let source = Self.terminalAppleScript(launchPath: shell.launchPath, arguments: shell.arguments)
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Builds the `tell application "Terminal" … do script "…"` AppleScript for a
    /// shell command. `launchPath`/`arguments` include untrusted plugin values
    /// (`bash=`, `paramN=`), so each token is POSIX single-quote escaped — making
    /// it inert to the shell regardless of spaces, quotes, `;`, `$()`, etc. — and
    /// the whole command is then escaped for the AppleScript string layer so it
    /// cannot terminate the `do script "…"` statement (the old code only quoted
    /// tokens containing a space and never escaped embedded quotes or newlines,
    /// which allowed both shell and AppleScript injection on click).
    nonisolated static func terminalAppleScript(launchPath: String, arguments: [String]) -> String {
        let command = ([launchPath] + arguments).map(shellQuote).joined(separator: " ")
        return "tell application \"Terminal\"\nactivate\ndo script \"\(appleScriptEscape(command))\"\nend tell"
    }

    /// POSIX single-quote quoting: wrap in `'…'`, rewriting each embedded `'` as
    /// `'\''`. The result is safe to paste into any POSIX shell verbatim.
    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding inside an AppleScript `"…"` literal.
    nonisolated static func appleScriptEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
