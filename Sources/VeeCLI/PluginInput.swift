import Foundation
import VeeRuntime

/// The two ways a path becomes plugin output, and the single place that choice
/// is made.
///
/// It is more than a convenience flag. Which mode produced the output decides
/// what a diagnostic's line number *means*, and therefore what file a compact
/// finding may name — see `PluginInput.Loaded.diagnosticPath`.
public enum InputMode: Sendable {
    /// Run the file and take its stdout. The default, and what every existing
    /// subcommand does.
    case execute
    /// Read the file and treat its contents as plugin output. Nothing is
    /// executed, so the file needs no execute bit and no shebang, and a save
    /// carries no risk of running arbitrary code.
    case text
}

/// Loads a path as plugin output under either mode.
public enum PluginInput {
    public struct Loaded: Sendable {
        /// The raw plugin output to parse.
        public let raw: String
        /// The path a compact diagnostic may be attributed to.
        ///
        /// In `.text` mode the author's file *is* the output, so an output line
        /// number is a line of that file and an editor can place a squiggle
        /// exactly. In `.execute` mode there is no recoverable mapping back to
        /// the source (one statement may emit many lines), so this is a
        /// pseudo-path that resolves to no file.
        public let diagnosticPath: String
        /// The process result, or `nil` in `.text` mode where nothing ran.
        public let outcome: ProcessOutcome?
    }

    public static func load(
        path: String,
        mode: InputMode,
        runner: ProcessRunning
    ) async throws -> Loaded {
        switch mode {
        case .text:
            let raw = try String(contentsOfFile: path, encoding: .utf8)
            return Loaded(raw: raw, diagnosticPath: path, outcome: nil)
        case .execute:
            let outcome = try await VeeCLI.runPlugin(path: path, runner: runner)
            return Loaded(
                raw: outcome.standardOutput,
                diagnosticPath: DiagnosticFormatter.stdoutPseudoPath,
                outcome: outcome)
        }
    }
}
