import Foundation
import VeeCore

/// Runs a plugin once and returns its raw output. Builds the launch command
/// (bash-wrapped by default, like SwiftBar's RunInBash), injects the
/// environment, and delegates to a `ProcessRunning`.
public struct PluginExecutor: Sendable {
    /// Applied when nothing more specific is given — i.e. a plugin declares no
    /// `<vee.timeout>` header and the caller passes no explicit override.
    /// `PluginRuntime.refresh` checks the header first and falls back to this.
    public static let defaultTimeout: TimeInterval = 30

    private let runner: ProcessRunning
    private let baseEnvironment: [String: String]

    public init(runner: ProcessRunning, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runner = runner
        self.baseEnvironment = baseEnvironment
    }

    /// - Parameters:
    ///   - runInBash: when false, the file is executed directly (respecting its
    ///     shebang). When true (for non-executable files), Vee honors the file's
    ///     shebang interpreter if it has one — so a non-`+x` Python/Node/Ruby
    ///     plugin runs with the right interpreter — and only falls back to
    ///     `/bin/bash <path>` when there's no shebang.
    ///   - timeout: wall-clock limit before the process is killed (SIGTERM,
    ///     then SIGKILL — see `SystemProcessRunner`). Defaults to
    ///     `defaultTimeout`; pass a plugin's `<vee.timeout>` override here
    ///     (`PluginRuntime.refresh` does this automatically).
    public func run(
        pluginPath: String,
        context: RuntimeEnvironmentContext,
        runInBash: Bool = true,
        timeout: TimeInterval? = PluginExecutor.defaultTimeout
    ) async throws -> ProcessOutcome {
        let (launchPath, arguments) = Self.launchCommand(pluginPath: pluginPath, runInBash: runInBash)
        let invocation = ProcessInvocation(
            launchPath: launchPath,
            arguments: arguments,
            environment: EnvironmentBuilder.merged(base: baseEnvironment, context: context),
            workingDirectory: (pluginPath as NSString).deletingLastPathComponent,
            timeout: timeout
        )
        return try await runner.run(invocation)
    }

    /// Chooses how to launch a plugin: direct exec, its shebang interpreter, or
    /// bash as a last resort.
    public static func launchCommand(pluginPath: String, runInBash: Bool) -> (path: String, arguments: [String]) {
        if !runInBash { return (pluginPath, []) }
        if let (interpreter, args) = shebang(of: pluginPath) {
            return (interpreter, args + [pluginPath])
        }
        return ("/bin/bash", [pluginPath])
    }

    /// Parses a `#!interpreter [arg]` first line, if present.
    static func shebang(of path: String) -> (interpreter: String, args: [String])? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 256)) ?? Data()
        guard let firstLine = String(data: data, encoding: .utf8)?
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
            firstLine.hasPrefix("#!") else { return nil }
        let tokens = firstLine.dropFirst(2).split(separator: " ").map(String.init)
        guard let interpreter = tokens.first else { return nil }
        return (interpreter, Array(tokens.dropFirst()))
    }
}
