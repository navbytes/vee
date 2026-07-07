import Foundation

/// Classifies the process arguments into a subcommand (or the absence of one).
///
/// The critical guarantee: launching the app (double-click, `open`, or with no
/// args) must NOT be misread as a CLI invocation, so the menu-bar app still
/// boots. LaunchServices passes a `-psn_0_123` process-serial-number argument
/// when double-launching a bundle; that, an empty arg list, or a leading flag
/// all classify as "no subcommand" (the app-launch path).
public enum SubcommandClassification: Equatable, Sendable {
    /// A recognised CLI subcommand plus the arguments that follow it.
    case subcommand(name: String, rest: [String])
    /// `--help`/`-h` or `--version` at the top level: a CLI request, but not a
    /// subcommand.
    case topLevelFlag(String)
    /// No CLI subcommand — fall through to the app-launch path.
    case none
}

public enum ArgumentClassifier {
    /// The subcommands the CLI understands.
    public static let knownSubcommands: Set<String> = ["render", "lint", "new", "search"]

    /// Classifies `arguments`, which INCLUDE the executable name as element 0
    /// (i.e. pass `CommandLine.arguments` directly).
    public static func classify(_ arguments: [String]) -> SubcommandClassification {
        // Drop the executable path (element 0).
        let args = Array(arguments.dropFirst())
        return classifyBare(args)
    }

    /// Classifies arguments that do NOT include the executable name.
    public static func classifyBare(_ args: [String]) -> SubcommandClassification {
        // Find the first argument that isn't a flag. A LaunchServices
        // `-psn_…` argument is a flag (starts with `-`), so it is skipped and
        // leaves us with no subcommand → app-launch path.
        guard let first = args.first else { return .none }

        if first == "--help" || first == "-h" || first == "--version" {
            return .topLevelFlag(first)
        }

        // Anything starting with `-` (including `-psn_0_123`) at the front is
        // not a subcommand; treat as no-subcommand so the app boots.
        if first.hasPrefix("-") { return .none }

        if knownSubcommands.contains(first) {
            return .subcommand(name: first, rest: Array(args.dropFirst()))
        }

        // A non-flag first token that isn't a known subcommand is still a CLI
        // usage attempt (e.g. `vee bogus`) — surface usage rather than boot the
        // app, so typos don't silently launch the menu bar.
        return .subcommand(name: first, rest: Array(args.dropFirst()))
    }
}
