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

    /// - Parameters:
    ///   - runInBash: overrides the run mode; when `nil`, falls back to
    ///     the header's `<swiftbar.runInBash>`, then to `true`.
    ///   - timeout: overrides the execution timeout; when `nil`, falls back to
    ///     the header's `<vee.timeout>`, then to `PluginExecutor.defaultTimeout`.
    public func refresh(
        pluginPath: String,
        context: RuntimeEnvironmentContext,
        header: HeaderMetadata? = nil,
        runInBash: Bool? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> PluginRunResult {
        let effectiveRunInBash = runInBash ?? header?.runInBash ?? true
        let effectiveTimeout = timeout ?? header?.timeout ?? PluginExecutor.defaultTimeout
        let outcome = try await executor.run(
            pluginPath: pluginPath,
            context: context,
            runInBash: effectiveRunInBash,
            timeout: effectiveTimeout
        )
        var parsed = OutputParser.parseAuto(outcome.standardOutput)
        // SystemProcessRunner's 8 MB capture cap silently dropped the rest of
        // the output before this; surface it through the same diagnostics
        // channel the debug console already reads, instead of leaving it silent.
        if outcome.outputTruncated {
            parsed.diagnostics.append(ParseDiagnostic(severity: .warning, message: "Output truncated at 8 MB"))
        }
        return PluginRunResult(output: parsed, outcome: outcome)
    }
}
