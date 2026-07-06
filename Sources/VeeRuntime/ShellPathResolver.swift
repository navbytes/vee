import Foundation

/// Resolves a usable `PATH` for plugin execution.
///
/// A GUI app launched from Finder/Dock inherits a minimal `PATH`
/// (`/usr/bin:/bin:/usr/sbin:/sbin`) that omits Homebrew and version-manager
/// shims (pyenv/asdf/nvm). That is the classic "works in Terminal, not in the
/// launcher" failure. We recover the user's real interactive `PATH` by asking
/// their login shell for it, then make sure the well-known tool directories are
/// present as a backstop.
public enum ShellPathResolver {
    /// Tool directories a GUI-launched app is most likely missing. Appended (if
    /// they exist on disk) after whatever the shell reports, so they never
    /// shadow the user's own ordering.
    static let knownDirectories = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
    ]

    private static let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// Returns `base` with its `PATH` replaced by the resolved, augmented value.
    /// Resolution failures degrade gracefully to the augmented current `PATH`.
    public static func resolvedEnvironment(
        runner: ProcessRunning = SystemProcessRunner(),
        base: [String: String] = ProcessInfo.processInfo.environment
    ) async -> [String: String] {
        let shell = base["SHELL"] ?? "/bin/zsh"
        let current = base["PATH"] ?? fallbackPath
        let path = await resolvePath(shell: shell, runner: runner, base: base, current: current)
        var env = base
        env["PATH"] = path
        return env
    }

    /// Asks the login shell for its `PATH` (`<shell> -ilc 'printf %s "$PATH"'`),
    /// then augments it. Any failure/timeout falls back to `current`.
    static func resolvePath(
        shell: String,
        runner: ProcessRunning,
        base: [String: String],
        current: String
    ) async -> String {
        let invocation = ProcessInvocation(
            launchPath: shell,
            // -i loads the interactive rc files (where pyenv/asdf/nvm/brew set
            // PATH); -l makes it a login shell; -c runs the command and exits.
            arguments: ["-ilc", "printf %s \"$PATH\""],
            environment: base,
            timeout: 4
        )
        var resolved = current
        if let outcome = try? await runner.run(invocation), !outcome.timedOut, outcome.exitCode == 0 {
            let out = outcome.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty { resolved = out }
        }
        return augment(resolved, home: base["HOME"])
    }

    /// Appends any missing `knownDirectories` (and `~/.local/bin`) that exist on
    /// disk to `path`, preserving order and removing duplicates.
    public static func augment(
        _ path: String,
        home: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ dir: String) {
            guard !dir.isEmpty, !seen.contains(dir) else { return }
            seen.insert(dir)
            result.append(dir)
        }
        for dir in path.split(separator: ":").map(String.init) { add(dir) }
        var extras = knownDirectories
        if let home, !home.isEmpty { extras.append(home + "/.local/bin") }
        for dir in extras where fileExists(dir) { add(dir) }
        return result.joined(separator: ":")
    }
}
