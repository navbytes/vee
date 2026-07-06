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
            } else if c == "|" {
                return (String(chars[0..<i]), String(chars[(i + 1)...]))
            }
            i += 1
        }
        return (line, nil)
    }

    /// Counts top-level `|` characters (not inside a quoted value).
    private static func topLevelPipeCount(_ s: String) -> Int {
        var count = 0
        var quote: Character?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "|" {
                count += 1
            }
            i = s.index(after: i)
        }
        return count
    }

    private static func analyzeParams(_ paramString: String, line: Int) -> [ParseDiagnostic] {
        var out: [ParseDiagnostic] = []
        var seenUnknown: Set<String> = []
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

    /// The parameter keys the parser recognises (mirrors `LineParser.mapParams`).
    private static let knownParams: Set<String> = [
        "color", "font", "size", "length", "trim", "ansi", "emojize",
        "href", "shell", "bash", "terminal", "refresh", "dropdown",
        "alternate", "disabled", "key", "image", "templateimage",
        "sfimage", "sfcolor", "sfsize", "sfconfig", "symbolize", "tooltip",
        "md", "markdown", "checked", "badge", "webview", "webvieww",
        "webviewh", "shortcut", "sparkline", "toggle", "slider", "progress",
        "trackcolor", "progressw", "progressh"
    ]

    private static func isKnownParam(_ key: String) -> Bool {
        if knownParams.contains(key) { return true }
        // Positional shell params: param1..N.
        if key.hasPrefix("param"), Int(key.dropFirst(5)) != nil { return true }
        return false
    }
}
