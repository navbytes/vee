import Foundation
import VeePluginFormat

/// How `vee lint` renders its findings.
public enum DiagnosticFormat: String, Sendable {
    /// The prose form Vee has always printed: `  error [line 12]: message`.
    case human
    /// `path:line:col: severity: message` — the shape VS Code's
    /// `problemMatcher`, vim's `errorformat`, and emacs compilation-mode all
    /// already parse, so findings become inline diagnostics with no
    /// Vee-specific editor plugin.
    case compact
}

/// Pure rendering of `ParseDiagnostic`s. No I/O, so both output forms are
/// unit-tested directly.
public enum DiagnosticFormatter {
    /// The path compact findings are attributed to when they describe the
    /// **output of an executed script** rather than a file the author can edit.
    ///
    /// Diagnostics are computed over a plugin's stdout. For an executed script
    /// the output-line → source-line mapping is many-to-one and unrecoverable —
    /// one `echo` inside a loop emits many rows — so naming the script would put
    /// squiggles on lines that have nothing wrong with them. This resolves to no
    /// file, so an editor lists the finding and marks nothing. Unhelpful is
    /// acceptable; confidently wrong is not.
    public static let stdoutPseudoPath = "<stdout>"

    /// Renders findings, one per line, each newline-terminated. Empty input
    /// produces an empty string in both forms — a caller printing a header must
    /// decide for itself whether there is anything to head.
    public static func render(
        _ diagnostics: [ParseDiagnostic],
        format: DiagnosticFormat,
        path: String
    ) -> String {
        diagnostics.map { line($0, format: format, path: path) + "\n" }.joined()
    }

    /// One finding. `human` is byte-for-byte what `vee lint` printed before the
    /// format flag existed.
    public static func line(
        _ d: ParseDiagnostic,
        format: DiagnosticFormat,
        path: String
    ) -> String {
        let severity = d.severity == .error ? "error" : "warning"
        switch format {
        case .human:
            if let line = d.line {
                return "  \(severity) [line \(line)]: \(d.message)"
            }
            return "  \(severity): \(d.message)"
        case .compact:
            // `ParseDiagnostic` carries no column, so the column is always 1. A
            // finding with no line is attributed to line 1 rather than dropped:
            // an editor must never be handed an out-of-range line, and a
            // finding the author cannot see is worse than one on the wrong line
            // of a file that has no right line.
            return "\(path):\(d.line ?? 1):1: \(severity): \(d.message)"
        }
    }

    /// Findings ordered for display: by line, then message. Line-less findings
    /// sort first.
    public static func sorted(_ diagnostics: [ParseDiagnostic]) -> [ParseDiagnostic] {
        diagnostics.sorted { ($0.line ?? 0, $0.message) < ($1.line ?? 0, $1.message) }
    }
}
