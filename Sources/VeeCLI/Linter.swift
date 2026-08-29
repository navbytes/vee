import Foundation
import VeePluginFormat

/// A pure linter over a plugin's raw stdout. Catches authoring mistakes the
/// permissive parser degrades past silently:
///
///  - a bare `|` in a title line's text half (a stray pipe not acting as the
///    param separator),
///  - an unquoted parameter value that contains a space (the exact bug class
///    the SDK builders prevent by auto-quoting),
///  - unknown parameter keys (deduped against the parser's own diagnostics).
///
/// Returns `ParseDiagnostic`s with 1-based line numbers. No I/O — testable in
/// isolation.
public enum Linter {
    public static func lint(rawOutput: String) -> [ParseDiagnostic] {
        var diagnostics: [ParseDiagnostic] = []

        var lines = rawOutput.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        // Tolerate CRLF line endings (Windows-authored scripts), same fix as
        // OutputParser.splitLines: strip exactly one trailing "\r" per line so
        // `---\r` still matches the separator check below. `.whitespaces`
        // trimming doesn't catch "\r", and without this every line would stay
        // (wrongly) classified as being above the separator.
        lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

        // Track whether we're above or below the first top-level `---` so we can
        // reason about title lines (bare `|` only matters in a title's text).
        var inBody = false

        for (index, rawLine) in lines.enumerated() {
            let lineNo = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" { inBody = true; continue }
            if trimmed.isEmpty { continue }

            // Body items may be prefixed with leading dashes (submenu depth);
            // strip them for param analysis. Separators (all dashes) are skipped.
            let content = inBody ? stripLeadingDashes(rawLine) : rawLine
            if inBody, content.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let (_, paramHalf) = splitOnFirstPipe(content)

            // 1. Bare `|` in a title line's text. The parser splits the title on
            //    the FIRST top-level `|` and treats everything after as params;
            //    a SECOND top-level `|` means the author's intended title text
            //    contained a pipe that is now being mis-parsed as a parameter
            //    separator. Flag it so they quote or remove it.
            if !inBody, let paramHalf, topLevelPipeCount(paramHalf) >= 1 {
                diagnostics.append(.init(
                    severity: .warning,
                    message: "stray '|' in title text; the first '|' separates title from parameters, so a later '|' is mis-parsed — quote or remove it",
                    line: lineNo))
            }

            guard let paramHalf else { continue }

            // 2 & 3. Re-tokenize the parameter string to catch unquoted-space
            //        values and unknown keys.
            for finding in analyzeParams(paramHalf, line: lineNo) {
                diagnostics.append(finding)
            }
        }

        return diagnostics
    }

    // MARK: - Helpers

    private static func stripLeadingDashes(_ line: String) -> String {
        let dashCount = line.prefix { $0 == "-" }.count
        return String(line.dropFirst(dashCount))
    }

    /// Splits on the first top-level `|` that is not inside a quoted value.
    /// Returns `(textHalf, paramHalf?)` where `paramHalf` is nil when there is
    /// no separator pipe.
    private static func splitOnFirstPipe(_ line: String) -> (text: String, params: String?) {
        let chars = Array(line)
        var i = 0
        var quote: Character?
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == "\\", i + 1 < chars.count, chars[i + 1] == q { i += 2; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "\\", i + 1 < chars.count, LineEscape.unescape(chars[i + 1]) != nil {
                // An escaped `\|` is display text, not the separator — the same
                // rule `LineParser.splitTextAndParams` applies, taken from the
                // same definition so the two cannot drift.
                i += 2
                continue
            } else if c == "|" {
                return (String(chars[0..<i]), String(chars[(i + 1)...]))
            }
            i += 1
        }
        return (line, nil)
    }

    /// Counts top-level `|` characters — not inside a quoted value, and not
    /// escaped as `\|`. Escaped pipes are display text the parser handles
    /// correctly, so counting them here is what produced a "stray '|'" warning
    /// on output Vee's own bundled SDKs emit.
    private static func topLevelPipeCount(_ s: String) -> Int {
        let chars = Array(s)
        var count = 0
        var quote: Character?
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "\\", i + 1 < chars.count, LineEscape.unescape(chars[i + 1]) != nil {
                i += 2
                continue
            } else if c == "|" {
                count += 1
            }
            i += 1
        }
        return count
    }

    private static func analyzeParams(_ paramString: String, line: Int) -> [ParseDiagnostic] {
        var out: [ParseDiagnostic] = []
        var seenUnknown: Set<String> = []
        var seenDeprecated: Set<String> = []
        let chars = Array(paramString)
        var i = 0

        func skipSpaces() { while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 } }

        while true {
            skipSpaces()
            if i >= chars.count { break }

            var key = ""
            while i < chars.count, chars[i] != "=", chars[i] != " " {
                key.append(chars[i]); i += 1
            }
            guard i < chars.count, chars[i] == "=" else {
                // Stray token with no value — the parser already warns; skip.
                while i < chars.count, chars[i] != " " { i += 1 }
                continue
            }
            i += 1 // consume '='

            let lowerKey = key.lowercased()
            var wasQuoted = false
            var valueHadSpace = false

            if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                wasQuoted = true
                let q = chars[i]; i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == q { i += 2; continue }
                    if chars[i] == q { i += 1; break }
                    i += 1
                }
            } else {
                // Bare value: read to next space. A bare value can never itself
                // contain a space, but the AUTHOR may have intended one — detect
                // it by peeking whether the following token looks like a
                // continuation rather than a new key=value pair.
                var value = ""
                while i < chars.count, chars[i] != " " {
                    value.append(chars[i]); i += 1
                }
                // Look ahead: if the next non-space token has no '=', it's a
                // continuation word of an unquoted value that should have been
                // quoted.
                let save = i
                skipSpaces()
                if i < chars.count {
                    var peek = ""
                    var j = i
                    while j < chars.count, chars[j] != " " { peek.append(chars[j]); j += 1 }
                    if !peek.contains("=") {
                        valueHadSpace = true
                    }
                }
                i = save
            }

            if valueHadSpace, !wasQuoted {
                out.append(.init(
                    severity: .warning,
                    message: "value for '\(lowerKey)' contains a space but isn't quoted; wrap it in quotes (e.g. \(lowerKey)=\"a b\")",
                    line: line))
            }

            if let current = Self.deprecatedParams[lowerKey], !seenDeprecated.contains(lowerKey) {
                seenDeprecated.insert(lowerKey)
                out.append(.init(
                    severity: .warning,
                    message: "'\(lowerKey)' is deprecated; use '\(current)'. The old spelling still "
                        + "works and will be removed in the next major version.",
                    line: line))
            }

            if !isKnownParam(lowerKey), !seenUnknown.contains(lowerKey) {
                seenUnknown.insert(lowerKey)
                out.append(.init(
                    severity: .warning,
                    message: "unknown parameter '\(lowerKey)'",
                    line: line))
            }
        }

        return out
    }

    /// Parameter spellings that still parse but are on the way out, mapped to
    /// the name that replaced them. Flagged so a plugin gets a migration
    /// prompt from `vee lint` during the deprecation window rather than a
    /// silent break when the old name is finally removed.
    private static let deprecatedParams: [String: String] = [
        "trackcolor": "progresstrackcolor"
    ]

    /// Whether the linter treats `key` as known. Delegates to
    /// `VeePluginFormat.LineParameterKeys` rather than keeping a second copy of
    /// the list — that mirror drifted from the published reference once already.
    private static func isKnownParam(_ key: String) -> Bool {
        LineParameterKeys.isRecognized(key)
    }

    // MARK: - Retired-SDK tombstone

    /// Flags a plugin's own source for an import of the now-retired official
    /// SDK. A sibling `vee.py`/`vee.ts` beside it keeps the plugin running
    /// forever by plain language precedence (Python checks the script's own
    /// directory first; a relative `./vee.ts` names a file directly) — so that
    /// case is only a warning that the copy is frozen. With no sibling the
    /// import cannot resolve anywhere, which is an error.
    ///
    /// Detects on the plugin's own source, not its stdout — the two `Linter`
    /// entry points look at different halves of the same plugin.
    public static func lintSDKImport(path: String, source: String, fileManager: FileManager = .default) -> [ParseDiagnostic] {
        let ext = (path as NSString).pathExtension.lowercased()
        let sibling: String
        switch ext {
        case "py":
            guard source.range(of: #"(?m)^\s*(from\s+vee\s+import\s|import\s+vee\b)"#, options: .regularExpression) != nil else { return [] }
            sibling = "vee.py"
        case "ts", "js", "mjs", "mts", "cjs":
            guard source.range(of: #"['"](@navbytes/vee|\./vee(\.ts|\.js)?)['"]"#, options: .regularExpression) != nil else { return [] }
            sibling = "vee.ts"
        default:
            return []
        }

        let siblingPath = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(sibling)
        if fileManager.fileExists(atPath: siblingPath) {
            return [.init(
                severity: .warning,
                message: "imports the retired Vee SDK; the sibling '\(sibling)' beside it is a frozen copy that keeps working — see the migration guide")]
        }
        return [.init(
            severity: .error,
            message: "the SDK is retired and this plugin cannot run — port to JSON output, see the migration guide (docs/_content/sdk.md)")]
    }
}
