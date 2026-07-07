import Foundation

/// Extracts `<xbar.*>` / `<swiftbar.*>` metadata from a plugin's source. The
/// tags live inside language-specific comments, but they can be scanned
/// directly regardless of comment syntax, so this is language-agnostic.
public enum HeaderParser {
    // Compile-time-constant pattern; cannot fail at runtime.
    // swiftlint:disable:next force_try
    private static let tag = try! NSRegularExpression(
        pattern: "<(xbar|swiftbar|vee)\\.([a-zA-Z.]+)>([\\s\\S]*?)</\\1\\.\\2>",
        options: []
    )

    // Compile-time-constant pattern; cannot fail at runtime.
    // swiftlint:disable:next force_try
    private static let varPattern = try! NSRegularExpression(
        pattern: "^\\s*(string|number|boolean|select)\\(([^=]+)=(.*?)\\)\\s*:?\\s*(.*?)\\s*(?:\\[(.*)\\])?\\s*$",
        options: []
    )

    private static let secretHints = ["token", "secret", "password", "passwd", "apikey", "api_key"]

    public static func parse(source: String) -> HeaderMetadata {
        var meta = HeaderMetadata()
        let ns = source as NSString

        for match in tag.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 2)).lowercased()
            let value = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "title": meta.title = value
            case "version": meta.version = value
            case "author": meta.author = value
            case "author.github": meta.authorGithub = value
            case "desc": meta.summary = value
            case "image": meta.image = value
            case "dependencies": meta.dependencies = splitList(value)
            // Plugin-declared; scheme-filtered like href= so the About dialog's
            // "Open Website" can't open file://, javascript:, etc.
            case "abouturl": meta.aboutURL = URL(string: value).flatMap { URLScheme.isSafeToOpen($0) ? $0 : nil }
            case "schedule": meta.schedule = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            case "runinbash": meta.runInBash = boolValue(value)
            case "refreshonopen": meta.refreshOnOpen = boolValue(value)
            case "type": meta.streamable = value.lowercased() == "streamable"
            case "environment": meta.environment = parseEnvironment(value)
            case "persistentwebview": meta.persistentWebView = boolValue(value)
            case "hideabout": meta.hideAbout = boolValue(value)
            case "hideruninterminal": meta.hideRunInTerminal = boolValue(value)
            case "hidelastupdated": meta.hideLastUpdated = boolValue(value)
            case "hidedisableplugin": meta.hideDisablePlugin = boolValue(value)
            case "hideswiftbar": meta.hideSwiftBar = boolValue(value)
            // Vee-native: opt into the searchable filter panel (`<vee.filter>`).
            case "filter": meta.filter = boolValue(value)
            case "var":
                if let decl = parseVar(value) { meta.vars.append(decl) }
            default:
                break
            }
        }
        return meta
    }

    private static func boolValue(_ v: String) -> Bool { ["true", "1", "yes"].contains(v.lowercased()) }

    private static func splitList(_ v: String) -> [String] {
        v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Parses `[VAR1=a, VAR2=b]` or `VAR1=a,VAR2=b`.
    private static func parseEnvironment(_ v: String) -> [String: String] {
        var trimmed = v.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") { trimmed.removeFirst() }
        if trimmed.hasSuffix("]") { trimmed.removeLast() }
        var env: [String: String] = [:]
        for pair in trimmed.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            env[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
        }
        return env
    }

    private static func parseVar(_ decl: String) -> VarDeclaration? {
        let ns = decl as NSString
        guard let m = varPattern.firstMatch(in: decl, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r).trimmingCharacters(in: .whitespaces)
        }
        guard let kind = VarDeclaration.Kind(rawValue: group(1)) else { return nil }
        let name = group(2)
        guard !name.isEmpty else { return nil }
        let options = group(5).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lname = name.lowercased()
        let isSecret = secretHints.contains { lname.contains($0) }
        return VarDeclaration(
            name: name,
            kind: kind,
            defaultValue: group(3),
            summary: group(4),
            options: options,
            isSecret: isSecret
        )
    }
}
