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
        if let shell = params.shell {
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
        let command = ([shell.launchPath] + shell.arguments)
            .map { $0.contains(" ") ? "'\($0)'" : $0 }
            .joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
