import Foundation
import VeePluginFormat
import VeeRuntime

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
            default:
                err += "vee: unknown subcommand '\(name)'\n\n"
                err += Usage.text
                return 2
            }
        }
    }

    static let version = "0.1.0"

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

        // Layer 1: the parser's own diagnostics.
        let parsed = OutputParser.parse(raw)
        findings += parsed.diagnostics

        // Layer 2: the raw-line linter (dedup unknown-param messages against
        // the parser's so a single mistake isn't reported twice).
        let parserMessages = Set(parsed.diagnostics.map(dedupKey))
        for finding in Linter.lint(rawOutput: raw) where !parserMessages.contains(dedupKey(finding)) {
            findings.append(finding)
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

    private static func dedupKey(_ d: ParseDiagnostic) -> String {
        "\(d.line.map(String.init) ?? "-"):\(d.message)"
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
      vee render <path>    Run a plugin and print its parsed menu tree.
      vee lint <path>      Run a plugin and report format/authoring problems.
      vee new [flags]      Scaffold a new plugin.

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
