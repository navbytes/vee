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
            case "search":
                return await runSearch(rest, runner: runner, out: &out, err: &err)
            case "show":
                return await runShow(rest, runner: runner, out: &out, err: &err)
            default:
                err += "vee: unknown subcommand '\(name)'\n\n"
                err += Usage.text
                return 2
            }
        }
    }

    static let version = "0.1.1"

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

    static func runLint(
        _ args: [String],
        runner: ProcessRunning,
        out: inout String,
        err: inout String
    ) async -> Int32 {
        guard let path = args.first(where: { !$0.hasPrefix("-") }) else {
            err += "vee lint: missing <path>\n\nUsage: vee lint <path>\n"
            return 2
        }

        // Run the plugin to obtain its raw output. (Reuses the same seam as
        // render so lint sees exactly what Vee would.)
        let raw: String
        do {
            let outcome = try await runPlugin(path: path, runner: runner)
            raw = outcome.standardOutput
            if outcome.exitCode != 0 {
                err += "Note: plugin exited with code \(outcome.exitCode).\n"
            }
        } catch {
            err += "vee lint: could not run '\(path)': \(error)\n"
            return 1
        }

        var findings: [ParseDiagnostic] = []

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

        if findings.isEmpty {
            out += "No lint findings.\n"
            return 0
        }

        out += "Lint findings:\n"
        for f in findings.sorted(by: sortDiagnostics) {
            out += format(f) + "\n"
        }
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
        if p.href != nil { return "href" }
        if let s = p.swiftbar.shortcut, !s.isEmpty { return "shortcut" }
        if p.refresh == true { return "refresh" }
        return "—"
    }

    // MARK: - show

    /// `vee show <plugin> [--once] [--no-color] [--dir DIR]` — render one plugin's
    /// menu-bar dropdown in the terminal (color, block progress bars, sparklines),
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

        let (filename, contents) = Scaffold.render(
            lang: resolvedLang,
            interval: resolvedInterval,
            name: resolvedName,
            trust: trust)

        if let dir = outDir {
            let path = (dir as NSString).appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try contents.write(toFile: path, atomically: true, encoding: .utf8)
                // Make shell/node/python plugins executable.
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                out += "Created \(path)\n"
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
        let invocation = ProcessInvocation(
            launchPath: launchPath,
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: (absolute as NSString).deletingLastPathComponent,
            timeout: 30)
        return try await runner.run(invocation)
    }

    // MARK: - Formatting helpers

    private static func format(_ d: ParseDiagnostic) -> String {
        let sev = d.severity == .error ? "error" : "warning"
        if let line = d.line {
            return "  \(sev) [line \(line)]: \(d.message)"
        }
        return "  \(sev): \(d.message)"
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
      vee new [flags]          Scaffold a new plugin.

    show flags:
      --once               Print a single frame instead of live-refreshing.
      --no-color           Disable ANSI color output.
      --dir DIR            Plugins folder to resolve a plugin name against.

    new flags:
      --lang ts|py|sh      Source language (default: sh).
      --interval 10s       Refresh interval embedded in the filename.
      --name NAME          Plugin name.
      --trust a,b,…        Declared capabilities (network,secrets,filesystem,exec,…).
      --out DIR            Write the plugin into DIR (otherwise printed to stdout).

    Other:
      --help, -h           Show this help.
      --version            Show the version.

    Running vee with no subcommand launches the menu-bar app.

    """
}
