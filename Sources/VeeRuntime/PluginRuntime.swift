import Foundation
import VeeCore
import VeePluginFormat

/// The result of refreshing a plugin: its parsed menu plus the raw process
/// outcome (for diagnostics / error surfaces).
public struct PluginRunResult: Sendable, Equatable {
    public var output: ParsedOutput
    public var outcome: ProcessOutcome

    public init(output: ParsedOutput, outcome: ProcessOutcome) {
        self.output = output
        self.outcome = outcome
    }
}

/// Ties execution to parsing: runs a plugin once and parses its stdout into a
/// `ParsedOutput`. Header metadata (when provided) selects the run mode.
public struct PluginRuntime: Sendable {
    private let executor: PluginExecutor

    public init(executor: PluginExecutor) {
        self.executor = executor
    }

    /// - Parameter runInBash: overrides the run mode; when `nil`, falls back to
    ///   the header's `<swiftbar.runInBash>`, then to `true`.
    public func refresh(
        pluginPath: String,
        context: RuntimeEnvironmentContext,
        header: HeaderMetadata? = nil,
        runInBash: Bool? = nil,
        timeout: TimeInterval? = 30
    ) async throws -> PluginRunResult {
        let effectiveRunInBash = runInBash ?? header?.runInBash ?? true
        let outcome = try await executor.run(
            pluginPath: pluginPath,
            context: context,
            runInBash: effectiveRunInBash,
            timeout: timeout
        )
        let parsed = OutputParser.parse(outcome.standardOutput)
        return PluginRunResult(output: parsed, outcome: outcome)
    }
}
