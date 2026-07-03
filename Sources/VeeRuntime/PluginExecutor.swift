import Foundation
import VeeCore

/// Runs a plugin once and returns its raw output. Builds the launch command
/// (bash-wrapped by default, like SwiftBar's RunInBash), injects the
/// environment, and delegates to a `ProcessRunning`.
public struct PluginExecutor: Sendable {
    private let runner: ProcessRunning
    private let baseEnvironment: [String: String]

    public init(runner: ProcessRunning, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runner = runner
        self.baseEnvironment = baseEnvironment
    }

    /// - Parameters:
    ///   - runInBash: when true (the default), the script is run as
    ///     `/bin/bash <path>` so it needs no execute bit and ignores its
    ///     shebang; when false the file is executed directly (respecting its
    ///     shebang, so Python/Ruby/… plugins work).
    public func run(
        pluginPath: String,
        context: RuntimeEnvironmentContext,
        runInBash: Bool = true,
        timeout: TimeInterval? = 30
    ) async throws -> ProcessOutcome {
        let invocation = ProcessInvocation(
            launchPath: runInBash ? "/bin/bash" : pluginPath,
            arguments: runInBash ? [pluginPath] : [],
            environment: EnvironmentBuilder.merged(base: baseEnvironment, context: context),
            workingDirectory: (pluginPath as NSString).deletingLastPathComponent,
            timeout: timeout
        )
        return try await runner.run(invocation)
    }
}
