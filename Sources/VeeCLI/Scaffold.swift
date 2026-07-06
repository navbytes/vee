import Foundation

/// Pure scaffolding for `vee new`. Generates a filename and a minimal, working
/// plugin body for the requested language, with an `<xbar.*>` metadata header
/// and any requested `<vee.*>` trust tags. The output must round-trip through
/// the parser with zero error diagnostics.
public enum Scaffold {
    public enum Language: String, CaseIterable, Sendable {
        case ts, py, sh

        public var ext: String { rawValue }

        static func parse(_ s: String) -> Language? {
            switch s.lowercased() {
            case "ts", "typescript", "js", "node": return .ts
            case "py", "python": return .py
            case "sh", "bash", "shell": return .sh
            default: return nil
            }
        }
    }

    /// Renders a plugin scaffold.
    ///
    /// - Parameters:
    ///   - lang: source language.
    ///   - interval: refresh interval token embedded in the filename (e.g. `5s`,
    ///     `10m`, `1h`).
    ///   - name: base plugin name (used for the filename and title).
    ///   - trust: comma-or-space-separated capability names (`network`,
    ///     `secrets`, `filesystem`, `exec`, `clipboard`, `notifications`).
    public static func render(lang: Language, interval: String, name: String, trust: [String]) -> (filename: String, contents: String) {
        let safeName = sanitize(name)
        let title = titleCase(name)
        let filename = "\(safeName).\(interval).\(lang.ext)"
        // The shebang must be line 1 for the interpreter to pick it up, so the
        // metadata/trust header (comments) follows it, then the body.
        let shebang = shebangLine(lang)
        let header = renderHeader(lang: lang, title: title, trust: trust)
        let body = renderBody(lang: lang, title: title)
        return (filename, shebang + "\n" + header + "\n\n" + body + "\n")
    }

    private static func shebangLine(_ lang: Language) -> String {
        switch lang {
        case .sh: return "#!/usr/bin/env bash"
        case .ts: return "#!/usr/bin/env node"
        case .py: return "#!/usr/bin/env python3"
        }
    }

    // MARK: - Header

    private static func renderHeader(lang: Language, title: String, trust: [String]) -> String {
        var meta: [String] = []
        meta.append("<xbar.title>\(title)</xbar.title>")
        meta.append("<xbar.version>1.0</xbar.version>")
        meta.append("<xbar.author>Your Name</xbar.author>")
        meta.append("<xbar.desc>\(title) — a Vee plugin.</xbar.desc>")

        // Trust tags: emit each requested capability. `network`/`secrets`/`exec`
        // get a detail tag so the author fills in specifics; others use the
        // capabilities list. Grammar per docs/_content/trust-model.md.
        var veeTags: [String] = []
        let caps = trust.map { $0.lowercased() }
        if caps.isEmpty {
            veeTags.append("<vee.capabilities></vee.capabilities>")
        } else {
            veeTags.append("<vee.capabilities>\(caps.joined(separator: ", "))</vee.capabilities>")
            if caps.contains("network") { veeTags.append("<vee.network>example.com</vee.network>") }
            if caps.contains("secrets") { veeTags.append("<vee.secrets>API_TOKEN</vee.secrets>") }
            if caps.contains("exec") { veeTags.append("<vee.exec>curl</vee.exec>") }
            if caps.contains("filesystem") { veeTags.append("<vee.filesystem.read>~/.config</vee.filesystem.read>") }
        }

        let all = meta + veeTags
        let commentPrefix = lang == .ts ? "//" : "#"
        return all.map { "\(commentPrefix) \($0)" }.joined(separator: "\n")
    }

    // MARK: - Body

    private static func renderBody(lang: Language, title: String) -> String {
        switch lang {
        case .sh:
            return shBody(title: title)
        case .ts:
            return tsBody(title: title)
        case .py:
            return pyBody(title: title)
        }
    }

    private static func shBody(title: String) -> String {
        """
        # Everything before the "---" line is the menu-bar title; everything
        # after is the dropdown. See docs/plugin-authoring for the full format.
        echo "\(title)"
        echo "---"
        echo "It works"
        echo "Refresh | refresh=true"
        """
    }

    private static func tsBody(title: String) -> String {
        // Seeds with the SDK import so `new` teaches the SDK.
        """
        import { Menu } from "./src/vee.ts";

        const menu = new Menu();
        menu.title("\(title)");

        const d = menu.dropdown;
        d.item("It works");
        d.item("Refresh", { refresh: true });

        process.stdout.write(menu.toString() + "\\n");
        """
    }

    private static func pyBody(title: String) -> String {
        """
        import os
        import sys

        sys.path.insert(0, os.path.dirname(__file__))
        from vee import Menu  # noqa: E402

        menu = Menu()
        menu.title("\(title)")

        d = menu.dropdown
        d.item("It works")
        d.item("Refresh", refresh=True)

        sys.stdout.write(menu.to_string() + "\\n")
        """
    }

    // MARK: - Name handling

    /// Reduces a display name to a filename-safe slug (lowercase, hyphenated).
    static func sanitize(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastWasDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastWasDash = false
            } else if !lastWasDash, !out.isEmpty {
                out.append("-"); lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "my-plugin" : out
    }

    /// Turns a raw name into a display title (used in the header/body).
    static func titleCase(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "My Plugin" : trimmed
    }
}
