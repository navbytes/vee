import Foundation
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeeSearch

/// Entry point for Vee's zero-install authoring subcommands: `render`, `lint`,
/// and `new`. All logic is AppKit-free and I/O is injected (buffers + a
/// `ProcessRunning`) so the whole surface is unit-testable.
public enum VeeCLI {
    /// Runs the CLI. `args` are the arguments AFTER the executable name.
    /// Writes to the provided buffers instead of real stdout/stderr and returns
    /// an exit code:
    ///   - `0` success,
    ///   - `1` render/lint findings,
    ///   - `2` usage error / unknown subcommand / `--help`.
    public static func run(
        _ args: [String],
        runner: ProcessRunning = SystemProcessRunner(),
        out: inout String,
        err: inout String
    ) async -> Int32 {
        switch ArgumentClassifier.classifyBare(args) {
        case .none:
            // No subcommand: from the CLI's perspective this is a usage error
            // (the executable's `main` handles the app-launch fall-through
            // before ever calling here).
            err += Usage.text
            return 2

        case .topLevelFlag(let flag):
            if flag == "--version" {
                out += "vee \(version)\n"
                return 0
            }
            out += Usage.text
            return 2

        case .subcommand(let name, let rest):
            switch name {
            case "render":
                return await runRender(rest, runner: runner, out: &out, err: &err)
            case "lint":
                return await runLint(rest, runner: runner, out: &out, err: &err)
            case "new":
                return runNew(rest, out: &out, err: &err)
            case "sdk":
                return runSDK(rest, out: &out, err: &err)
            case "search":
                return await runSearch(rest, runner: runner, out: &out, err: &err)
            case "show":
                return await runShow(rest, runner: runner, out: &out, err: &err)
            case "dev":
                return await runDev(rest, runner: runner, out: &out, err: &err)
            default:
                err += "vee: unknown subcommand '\(name)'\n\n"
                err += Usage.text
                return 2
            }
        }
    }

    // Read from the bundle so `vee --version` can't drift from the app it ships
    // inside; `fallbackVersion` (Version.swift, rewritten by the release
    // workflow) covers a binary with no bundle around it.
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallbackVersion

    // MARK: - sdk

    static let sdkUsage = "Usage: vee sdk <ts|py> [--out DIR]\n"

    /// `vee sdk <lang>` — write the plugin SDK for one language into a
    /// directory, so a plugin can import it as a sibling file.
    ///
    /// This is the counterpart to `vee new`, for a plugin that already exists —
    /// one copied out of the examples, most often. The examples import
    /// `../vee.ts` because they live beside the SDK in the repository; a copy
    /// of one needs its own sibling copy and a `./vee.ts` import.
    ///
    /// Go is deliberately unsupported: a Go plugin compiles to a binary and
    /// consumes the SDK as a normal module, so there is nothing to vendor.
    static func runSDK(_ args: [String], out: inout String, err: inout String) -> Int32 {
        var language: String?
        var outDir = FileManager.default.currentDirectoryPath
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--out":
                guard i + 1 < args.count else {
                    err += "vee sdk: --out needs a directory\n\n" + sdkUsage
                    return 2
                }
                outDir = args[i + 1]
                i += 1
            case "go", "golang":
                err += "vee sdk: Go does not vendor an SDK file — a Go plugin is a "
                err += "compiled binary, so it imports the module instead:\n\n"
                err += "  go get github.com/navbytes/vee/plugins/go\n"
                return 2
            default:
                if arg.hasPrefix("-") {
                    err += "vee sdk: unknown flag '\(arg)'\n\n" + sdkUsage
                    return 2
                }
                language = arg
            }
            i += 1
        }

        let resolved: String
        switch (language ?? "").lowercased() {
        case "ts", "typescript", "js", "node": resolved = "typescript"
        case "py", "python": resolved = "python"
        case "": err += "vee sdk: missing <lang>\n\n" + sdkUsage; return 2
        default:
            err += "vee sdk: unknown language '\(language ?? "")' (expected ts|py)\n\n" + sdkUsage
            return 2
        }

        guard let filename = EmbeddedSDK.filename(for: resolved),
              let source = EmbeddedSDK.source(for: resolved) else {
            err += "vee sdk: no embedded SDK for '\(resolved)'\n"
            return 1
        }

        let path = (outDir as NSString).appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            try source.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            err += "vee sdk: could not write '\(path)': \(error)\n"
            return 1
        }
        out += "Created \(path)\n"
        let importLine = resolved == "typescript"
            ? "import { Menu } from \"./vee.ts\";"
            : "from vee import Menu"
        out += "Import it from a plugin in this directory with:\n\n  \(importLine)\n"
        return 0
    }

    // MARK: - dev

    static let devUsage = "Usage: vee dev <path> [--text] [--push] [--no-color]\n"

    /// `vee dev <path>` — watch one file and repaint the menu Vee would build
    /// from it on every save. The interactive loop lives in `DevLoop`; this
    /// parses arguments and decides whether a loop is even possible.
    static func runDev(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        var mode = InputMode.execute
        var push = false
        var noColor = false
        var positionals: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--text": mode = .text
            case "--push": push = true
            case "--no-color": noColor = true
            default:
                if arg.hasPrefix("-") {
                    err += "vee dev: unknown flag '\(arg)'\n"
                    return 2
                }
                positionals.append(arg)
            }
            i += 1
        }

        guard let path = positionals.first else {
            err += "vee dev: missing <path>\n\n" + devUsage
            return 2
        }
        guard FileManager.default.fileExists(atPath: path) else {
            err += "vee dev: no such file '\(path)'\n"
            return 1
        }

        let stdoutIsTTY = isatty(FileHandle.standardOutput.fileDescriptor) != 0
        let stdinIsTTY = isatty(FileHandle.standardInput.fileDescriptor) != 0
        let colorEnabled = !noColor
            && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && stdoutIsTTY

        let target = push ? PushTarget(path: path) : nil

        // Without both a real terminal and real keyboard input there is no loop
        // to run: raw mode and the alternate screen would corrupt a pipe, and
        // nothing could ever ask it to quit. Print one frame instead — the same
        // seam `vee show` uses, and what makes this path testable.
        guard stdoutIsTTY, stdinIsTTY else {
            let snap = await DevLoop.snapshot(path: path, mode: mode, runner: runner)
            var notes: [String] = []
            if let target {
                notes = await target.send(snapshot: snap, runner: runner, isFirstPush: true)
                await target.teardown(runner: runner)
            }
            out += DevLoop.frame(
                snap,
                width: LiveView.terminalWidth(),
                color: colorEnabled,
                updatedAt: "--:--:--",
                extraNotes: notes)
            return DevLoop.exitCode(for: snap)
        }

        return await DevLoop.run(path: path, mode: mode, runner: runner, color: colorEnabled, push: target)
    }

    // MARK: - render

    static func runRender(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        guard let path = args.first(where: { !$0.hasPrefix("-") }) else {
            err += "vee render: missing <path>\n\nUsage: vee render <path>\n"
            return 2
        }

        let outcome: ProcessOutcome
        do {
            outcome = try await runPlugin(path: path, runner: runner)
        } catch {
            err += "vee render: could not run '\(path)': \(error)\n"
            return 1
        }

        let parsed = OutputParser.parseAuto(outcome.standardOutput)
        out += TreeRenderer.render(parsed)
        if !out.hasSuffix("\n") { out += "\n" }

        var hadProblem = false

        // Surface parse diagnostics.
        if !parsed.diagnostics.isEmpty {
            err += "\nDiagnostics:\n"
            for d in parsed.diagnostics { err += format(d) + "\n" }
            hadProblem = hadProblem || parsed.diagnostics.contains { $0.severity == .error }
        }

        // Surface runtime problems.
        if outcome.timedOut {
            err += "\nPlugin timed out.\n"
            hadProblem = true
        }
        if outcome.exitCode != 0 {
            err += "\nPlugin exited with code \(outcome.exitCode).\n"
            hadProblem = true
        }
        if !outcome.standardError.isEmpty {
            err += "\nPlugin stderr:\n" + outcome.standardError
            if !outcome.standardError.hasSuffix("\n") { err += "\n" }
        }

        return hadProblem ? 1 : 0
    }

    // MARK: - lint

    static let lintUsage = "Usage: vee lint <path> [--text] [--format human|compact]\n"

    static func runLint(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        var mode = InputMode.execute
        var format = DiagnosticFormat.human
        var positionals: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--text": mode = .text
            case "--format":
                i += 1
                guard i < args.count, let parsed = DiagnosticFormat(rawValue: args[i]) else {
                    err += "vee lint: --format expects 'human' or 'compact'\n"
                    return 2
                }
                format = parsed
            default:
                if arg.hasPrefix("-") {
                    err += "vee lint: unknown flag '\(arg)'\n"
                    return 2
                }
                positionals.append(arg)
            }
            i += 1
        }

        guard let path = positionals.first else {
            err += "vee lint: missing <path>\n\n" + lintUsage
            return 2
        }

        // Obtain the raw output: by running the plugin (the same seam render
        // uses, so lint sees exactly what Vee would) or, under `--text`, by
        // reading the file without executing anything.
        let loaded: PluginInput.Loaded
        do {
            loaded = try await PluginInput.load(path: path, mode: mode, runner: runner)
        } catch {
            let verb = mode == .text ? "read" : "run"
            err += "vee lint: could not \(verb) '\(path)': \(error)\n"
            return 1
        }
        let raw = loaded.raw

        var findings: [ParseDiagnostic] = []

        // A plugin that could not run is a lint failure, not a footnote. This
        // was a "Note:" on stderr with a 0 exit, so a plugin whose interpreter
        // was missing (exit 127) or that crashed on import linted clean and
        // sailed through CI — there is no output to find anything in. `render`
        // and `dev` already fail on both conditions; lint was the odd one out.
        if let outcome = loaded.outcome {
            if outcome.timedOut {
                // …except for a streaming plugin, which is *supposed* to run
                // forever: the CLI runs it as a one-shot, so hitting the
                // timeout is how it always ends. Flagging that would fail CI on
                // every correct streamable plugin.
                if !isStreamable(path: path) {
                    findings.append(.init(severity: .error, message: "plugin timed out before producing output"))
                }
            } else if outcome.exitCode != 0 {
                findings.append(.init(
                    severity: .error,
                    message: "plugin exited with code \(outcome.exitCode); only the output it managed to print was linted"))
            }
        }

        // Structured-JSON output (`{"vee":1,…}`) is a different protocol, and
        // the text-format linter and parser would scan it as xbar lines — every
        // literal `|` inside a JSON string value reads as a param separator, so
        // well-formed JSON came back buried in bogus "unknown parameter" and
        // "no value" findings. Take the JSON parser's own diagnostics instead.
        // Every other CLI path already routes through `parseAuto` for exactly
        // this reason; lint was the one that did not.
        if let json = JSONOutputParser.parse(raw) {
            findings += json.diagnostics
        } else {
            // The raw-line linter re-detects some issues the parser also flags (e.g.
            // unknown params), but with accurate line numbers — whereas the parser's
            // per-line mapping reports them line-less. So take the linter's findings
            // first, then add only the parser diagnostics whose message the linter
            // didn't already cover (deduping by message, since the same mistake
            // reported by both would otherwise appear twice). Final order is by line.
            let parsed = OutputParser.parse(raw)
            let linterFindings = Linter.lint(rawOutput: raw)
            findings += linterFindings

            let linterMessages = Set(linterFindings.map(\.message))
            for diagnostic in parsed.diagnostics where !linterMessages.contains(diagnostic.message) {
                findings.append(diagnostic)
            }
        }

        if findings.isEmpty {
            // Compact output is consumed by an editor, which wants findings and
            // nothing else — a prose "no findings" line would be parsed as junk.
            if format == .human { out += "No lint findings.\n" }
            return 0
        }

        if format == .human { out += "Lint findings:\n" }
        out += DiagnosticFormatter.render(
            DiagnosticFormatter.sorted(findings),
            format: format,
            path: loaded.diagnosticPath)
        return 1
    }

    // MARK: - search

    /// `vee search <path> [query…]` — run a plugin, flatten its (nested) menu into
    /// activatable rows, and print them fuzzy-filtered + ranked by the query, each
    /// with its breadcrumb and the action Enter would fire. With no query it lists
    /// every activatable item (the panel's idle state). Exercises `VeeSearch`
    /// end-to-end before the interactive panel exists.
    static func runSearch(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        let positional = args.filter { !$0.hasPrefix("-") }
        guard let path = positional.first else {
            err += "vee search: missing <path>\n\nUsage: vee search <path> [query…]\n"
            return 2
        }
        let query = positional.dropFirst().joined(separator: " ")

        let outcome: ProcessOutcome
        do {
            outcome = try await runPlugin(path: path, runner: runner)
        } catch {
            err += "vee search: could not run '\(path)': \(error)\n"
            return 1
        }

        let parsed = OutputParser.parseAuto(outcome.standardOutput)
        let rows = MenuSearch.flatten(parsed.body)
        let results = MenuSearch.search(query, in: rows)

        if query.isEmpty {
            out += "\(rows.count) activatable item(s):\n"
        } else {
            out += "\(results.count) of \(rows.count) item(s) match \"\(query)\":\n"
        }
        for row in results {
            var line = "  \(row.item.text)"
            if !row.breadcrumb.isEmpty { line += "  ⟨\(row.breadcrumb)⟩" }
            line += "  [\(actionLabel(row.item))]"
            out += line + "\n"
        }
        if results.isEmpty { out += "  (no matches)\n" }
        return results.isEmpty && !query.isEmpty ? 1 : 0
    }

    /// The action `AppActionDispatcher.perform` would take for this item, in its
    /// dispatch order — a hint for the search output.
    private static func actionLabel(_ item: MenuItem) -> String {
        let p = item.params
        if p.control != nil { return "control" }
        if p.shell != nil { return "shell" }
        if p.swiftbar.webview != nil { return "webview" }
        if p.sparkline != nil { return "sparkline" }
        if let chart = p.swiftbar.chart { return chart.kind.rawValue }
        if p.href != nil { return "href" }
        if let s = p.swiftbar.shortcut, !s.isEmpty { return "shortcut" }
        if p.refresh == true { return "refresh" }
        return "—"
    }

    // MARK: - show

    /// `vee show <plugin> [--once] [--no-color] [--dir DIR]` — render one plugin's
    /// menu-bar dropdown in the terminal (color, block progress bars, sparklines,
    /// segmented share charts),
    /// live-refreshing on the plugin's own filename cadence. `<plugin>` is a path
    /// or the name of an installed plugin. On a non-interactive stdout (a pipe, or
    /// `--once`) it prints a single frame and exits — the seam tests exercise.
    static func runShow(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        var once = false
        var noColor = false
        var dirOverride: String?
        var positionals: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--once": once = true
            case "--no-color": noColor = true
            case "--dir":
                i += 1
                if i < args.count { dirOverride = args[i] }
            default:
                if arg.hasPrefix("-") {
                    err += "vee show: unknown flag '\(arg)'\n"
                    return 2
                }
                positionals.append(arg)
            }
            i += 1
        }

        guard let argument = positionals.first else {
            err += "vee show: missing <plugin>\n\nUsage: vee show <plugin> [--once] [--no-color] [--dir DIR]\n"
            return 2
        }

        let directory = PluginResolver.pluginsDirectory(override: dirOverride)
        let resolved: PluginResolver.Resolved
        switch PluginResolver.resolve(
            argument: argument,
            directory: directory,
            currentDirectory: FileManager.default.currentDirectoryPath
        ) {
        case .success(let value):
            resolved = value
        case .failure(let error):
            switch error {
            case .fileNotFound(let path):
                err += "vee show: no such plugin file '\(path)'\n"
            case .nameNotFound(let name, let available):
                err += "vee show: no installed plugin named '\(name)'.\n"
                if available.isEmpty {
                    err += "  (no plugins found in \(directory))\n"
                } else {
                    err += "  available: \(available.joined(separator: ", "))\n"
                }
            }
            return 1
        }

        // Color and the live loop both require a real interactive stdout; a pipe
        // or `--once` takes the single-frame path (deterministic, testable).
        let stdoutIsTTY = isatty(FileHandle.standardOutput.fileDescriptor) != 0
        let stdinIsTTY = isatty(FileHandle.standardInput.fileDescriptor) != 0
        let colorEnabled = !noColor
            && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && stdoutIsTTY

        if once || !stdoutIsTTY || !stdinIsTTY {
            let width = terminalWidth()
            let result = await showBody(resolved: resolved, runner: runner, color: colorEnabled, width: width)
            out += result.status + "\n\n" + result.body
            if !out.hasSuffix("\n") { out += "\n" }
            return result.code
        }

        return await LiveView.run(resolved: resolved, runner: runner, color: colorEnabled)
    }

    /// Runs `resolved` once and renders it to a status line + a terminal-styled
    /// dropdown body, with any parse diagnostics / stderr surfaced as a dim
    /// footer. Shared by the single-frame path and the live loop.
    static func showBody(
        resolved: PluginResolver.Resolved,
        runner: ProcessRunning,
        color: Bool,
        width: Int
    ) async -> (status: String, body: String, code: Int32, timedOut: Bool) {
        let options = TerminalRenderer.Options(color: color, width: width)

        let outcome: ProcessOutcome
        do {
            outcome = try await runPlugin(path: resolved.path, runner: runner)
        } catch {
            let status = statusLine(name: resolved.displayName, interval: resolved.interval, code: 1, timedOut: false, color: color)
            let body = TerminalRenderer.dimmed("could not run plugin: \(error)", color: color)
            return (status, body, 1, false)
        }

        let parsed = OutputParser.parseAuto(outcome.standardOutput)
        var body = TerminalRenderer.render(parsed, options: options)

        var notes: [String] = []
        for d in parsed.diagnostics { notes.append(format(d)) }
        if outcome.timedOut { notes.append("  plugin timed out") }
        if !outcome.standardError.isEmpty {
            notes.append("  stderr: " + outcome.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !notes.isEmpty {
            let block = notes.map { TerminalRenderer.dimmed($0, color: color) }.joined(separator: "\n")
            body += (body.isEmpty ? "" : "\n\n") + block
        }

        let hadError = outcome.exitCode != 0 || outcome.timedOut || parsed.diagnostics.contains { $0.severity == .error }
        let status = statusLine(
            name: resolved.displayName,
            interval: resolved.interval,
            code: outcome.exitCode,
            timedOut: outcome.timedOut,
            color: color)
        return (status, body, hadError ? 1 : 0, outcome.timedOut)
    }

    /// A one-line plugin status banner: a health dot, the name, its refresh
    /// cadence, and the last exit code (or a timeout / non-zero flag).
    static func statusLine(name: String, interval: RefreshInterval, code: Int32, timedOut: Bool, color: Bool) -> String {
        let healthy = !timedOut && code == 0
        let dot = TerminalRenderer.colored("●", healthy ? .named("green") : .named("red"), color: color)
        var parts = [dot + " " + name, describeInterval(interval)]
        if timedOut {
            parts.append(TerminalRenderer.colored("timed out", .named("red"), color: color))
        } else if code != 0 {
            parts.append(TerminalRenderer.colored("exit \(code)", .named("red"), color: color))
        } else {
            parts.append(TerminalRenderer.dimmed("exit 0", color: color))
        }
        return parts.joined(separator: TerminalRenderer.dimmed("  ·  ", color: color))
    }

    /// Human-readable form of a plugin's refresh cadence.
    static func describeInterval(_ interval: RefreshInterval) -> String {
        switch interval {
        case .manual: return "manual"
        case .cron(let expr): return "cron \(expr)"
        case .milliseconds(let n): return "every \(n)ms"
        case .seconds(let n): return "every \(n)s"
        case .minutes(let n): return "every \(n)m"
        case .hours(let n): return "every \(n)h"
        case .days(let n): return "every \(n)d"
        }
    }

    /// Terminal width for the single-frame path (the live loop queries the TTY
    /// directly via `ioctl`).
    static func terminalWidth() -> Int {
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let n = Int(columns), n > 0 {
            return n
        }
        return 80
    }

    // MARK: - new

    static func runNew(_ args: [String], out: inout String, err: inout String) -> Int32 {
        var lang: String?
        var interval: String?
        var name: String?
        var trust: [String] = []
        var outDir: String?
        var force = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            func nextValue() -> String? {
                guard i + 1 < args.count else { return nil }
                i += 1
                return args[i]
            }
            switch arg {
            case "--lang": lang = nextValue()
            case "--interval": interval = nextValue()
            case "--name": name = nextValue()
            case "--out": outDir = nextValue()
            case "--force": force = true
            case "--trust":
                if let v = nextValue() {
                    trust += v.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
                }
            default:
                err += "vee new: unknown flag '\(arg)'\n"
                return 2
            }
            i += 1
        }

        // Prompt for missing values only on an interactive TTY, so tests (which
        // always pass flags) never block.
        let interactive = isatty(FileHandle.standardInput.fileDescriptor) != 0
        if interactive {
            if name == nil { name = prompt("Plugin name", default: "My Plugin") }
            if lang == nil { lang = prompt("Language (ts|py|sh)", default: "sh") }
            if interval == nil { interval = prompt("Refresh interval (e.g. 5s, 10m, 1h)", default: "10s") }
        }

        let resolvedLangString = lang ?? "sh"
        guard let resolvedLang = Scaffold.Language.parse(resolvedLangString) else {
            err += "vee new: unknown --lang '\(resolvedLangString)' (expected ts|py|sh)\n"
            return 2
        }
        let resolvedInterval = interval ?? "10s"
        let resolvedName = name ?? "My Plugin"

        // The interval is embedded in the filename, and a filename token Vee
        // can't parse is not an error at load time — it just means `.manual`.
        // So `--interval "5 minutes"` scaffolds a plugin that looks fine and
        // never refreshes, with nothing anywhere saying why. Warn here, where
        // the typo is still in the user's hands. Deliberately not fatal:
        // `name.<anything>.sh` remains a legal, manually-refreshed plugin.
        if RefreshInterval.parse(token: resolvedInterval) == nil {
            err += "vee new: warning: '\(resolvedInterval)' is not a refresh interval "
            err += "(expected e.g. 10s, 5m, 1h, 1d) — this plugin will only refresh on demand.\n"
        }

        let (filename, contents) = Scaffold.render(
            lang: resolvedLang,
            interval: resolvedInterval,
            name: resolvedName,
            trust: trust)

        if let dir = outDir {
            let path = (dir as NSString).appendingPathComponent(filename)
            // Refuse to clobber an existing plugin. The SDK vendored a few
            // lines below has always been protected this way ("Kept … already
            // present"); the plugin itself — the file with the user's actual
            // work in it — was the one being silently overwritten, and a
            // scaffold is generated from flags, so what it destroys is never
            // recoverable from what it writes.
            if !force, FileManager.default.fileExists(atPath: path) {
                err += "vee new: '\(path)' already exists — pass --force to overwrite it.\n"
                return 1
            }
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try contents.write(toFile: path, atomically: true, encoding: .utf8)
                // Make shell/node/python plugins executable.
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                out += "Created \(path)\n"

                // Vendor the SDK beside the plugin. Without this the scaffolded
                // plugin does not run: its import resolves to a sibling file
                // that would not exist. A Vee plugin is a single executable with
                // no install step, so the SDK travels with it.
                if let language = Scaffold.vendoredSDK(for: resolvedLang),
                   let sdkName = EmbeddedSDK.filename(for: language),
                   let sdkSource = EmbeddedSDK.source(for: language) {
                    let sdkPath = (dir as NSString).appendingPathComponent(sdkName)
                    if FileManager.default.fileExists(atPath: sdkPath) {
                        out += "Kept \(sdkPath) (already present)\n"
                    } else {
                        do {
                            try sdkSource.write(toFile: sdkPath, atomically: true, encoding: .utf8)
                            out += "Created \(sdkPath)\n"
                        } catch {
                            err += "vee new: could not write '\(sdkPath)': \(error)\n"
                            return 1
                        }
                    }
                }
                return 0
            } catch {
                err += "vee new: could not write '\(path)': \(error)\n"
                return 1
            }
        }

        // No --out: print the file to stdout so it can be redirected.
        out += "# \(filename)\n"
        out += contents
        return 0
    }

    // MARK: - Plugin running seam

    /// Runs a plugin file once via the injected runner, choosing the launch
    /// command the way `PluginExecutor` does (shebang/bash), with a timeout and
    /// working dir set to the plugin's directory.
    static func runPlugin(path: String, runner: ProcessRunning) async throws -> ProcessOutcome {
        // Resolve to an absolute path first: the working directory is set to the
        // plugin's own directory, so a relative path would fail to launch.
        let absolute = (path as NSString).isAbsolutePath
            ? path
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        let (launchPath, arguments) = PluginExecutor.launchCommand(pluginPath: absolute, runInBash: true)
        // The same SDK injection the app does, so a plugin behaves identically
        // under `vee render`/`vee dev` and under the menu bar. Without it an
        // author debugging a plugin that imports the SDK would see it fail here
        // and work there, or the reverse — the class of inconsistency that made
        // a clicked action resolve a different `$SWIFTBAR_PLUGIN_DATA_PATH`
        // than a render.
        let sdkRoot = SDKProvisioner.provision(into: SDKProvisioner.defaultRoot)
        var environment = ProcessInfo.processInfo.environment
        if let sdkRoot { environment = SDKProvisioner.apply(to: environment, root: sdkRoot) }
        let invocation = ProcessInvocation(
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: (absolute as NSString).deletingLastPathComponent,
            timeout: 30)
        return try await runner.run(invocation)
    }

    /// Whether the plugin at `path` declares `<*.type>streamable</*.type>`.
    /// Read from source because a streaming plugin's stdout says nothing about
    /// it — the frames look like any other output.
    static func isStreamable(path: String) -> Bool {
        guard let source = PluginSource.read(atPath: path) else { return false }
        return HeaderParser.parse(source: source).streamable
    }

    // MARK: - Formatting helpers

    /// The human form, delegated to `DiagnosticFormatter` so `render` and `lint`
    /// cannot drift from each other or from the compact form's severity naming.
    private static func format(_ d: ParseDiagnostic) -> String {
        DiagnosticFormatter.line(d, format: .human, path: "")
    }

    private static func sortDiagnostics(_ a: ParseDiagnostic, _ b: ParseDiagnostic) -> Bool {
        (a.line ?? 0, a.message) < (b.line ?? 0, b.message)
    }

    private static func prompt(_ label: String, default def: String) -> String {
        FileHandle.standardOutput.write(Data("\(label) [\(def)]: ".utf8))
        guard let line = readLine(strippingNewline: true), !line.isEmpty else { return def }
        return line
    }
}

/// Top-level usage text.
enum Usage {
    static let text = """
    vee — a native macOS menu-bar script runner (xbar successor).

    Usage:
      vee render <path>        Run a plugin and print its parsed menu tree.
      vee lint <path>          Run a plugin and report format/authoring problems.
      vee search <path> [q…]   Run a plugin and fuzzy-search its (nested) items.
      vee show <plugin>        Live-render a plugin's dropdown in the terminal.
      vee dev <path>           Watch a file and re-render it on every save.
      vee new [flags]          Scaffold a new plugin.
      vee sdk <ts|py> [--out]  Write the plugin SDK into a directory.

    show flags:
      --once               Print a single frame instead of live-refreshing.
      --no-color           Disable ANSI color output.
      --dir DIR            Plugins folder to resolve a plugin name against.

    dev flags:
      --text               Treat the file as plugin output; do not execute it.
      --push               Also show each save as a real Vee status item.
      --no-color           Disable ANSI color output.

    lint flags:
      --text               Treat the file as plugin output; do not execute it.
      --format FORMAT      human (default) or compact (path:line:col: …), which
                           editors parse into inline diagnostics.

    new flags:
      --lang ts|py|sh      Source language (default: sh).
      --interval 10s       Refresh interval embedded in the filename.
      --name NAME          Plugin name.
      --trust a,b,…        Declared capabilities (network,secrets,filesystem,exec,…).
      --out DIR            Write the plugin into DIR (otherwise printed to stdout).
      --force              Overwrite an existing plugin of the same name.

    Other:
      --help, -h           Show this help.
      --version            Show the version.

    Running vee with no subcommand launches the menu-bar app.

    """
}
