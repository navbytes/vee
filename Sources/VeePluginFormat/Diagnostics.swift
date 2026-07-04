import Foundation

/// A non-fatal problem found while parsing plugin output or headers. The parser
/// never throws on malformed input — it produces best-effort output plus
/// diagnostics, so a broken line degrades gracefully instead of hiding the
/// whole plugin.
public struct ParseDiagnostic: Equatable, Sendable {
    public enum Severity: Sendable, Equatable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    /// 1-based line number within the parsed source, when known.
    public let line: Int?

    public init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}
