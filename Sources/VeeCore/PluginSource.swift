import Foundation

/// Reading a plugin's script as text.
///
/// A plugin file is not guaranteed to be valid UTF-8. It is a script someone
/// wrote in whatever editor they had — a Latin-1 `é` in a comment, a stray byte
/// pasted from a terminal, a file saved in a legacy encoding. The kernel does
/// not care: `PluginExecutor` launches it through its shebang and it runs.
///
/// Everything that reads the same file *as a String* used to do it with a
/// strict `String(contentsOfFile:encoding:.utf8)` and `?? ""`, which turns one
/// bad byte anywhere in the file into an empty header: no `<xbar.var>`
/// declarations (so the settings form is blank and the plugin's environment
/// silently loses its configured values, Keychain secrets included), no
/// schedule, no timeout, no surface, no hotkey, and a trust level of
/// `undeclared` — indistinguishable from a plugin that honestly declared
/// nothing. The plugin still runs, with the wrong configuration and a shield
/// that misrepresents it.
///
/// A lossy decode is the honest reading: undecodable bytes become U+FFFD and
/// every header line around them parses exactly as it should.
public enum PluginSource {
    /// The plugin at `path` as text, decoding UTF-8 leniently.
    ///
    /// Throws only when the file cannot be read at all — missing, or no
    /// permission — which is a genuinely different condition from "read fine,
    /// wasn't valid UTF-8" and the one worth reporting. The error is
    /// Foundation's own, so callers keep its specific wording ("no such file",
    /// "you don't have permission") instead of a flattened stand-in.
    public static func readOrThrow(atPath path: String) throws -> String {
        String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
    }

    /// ``readOrThrow(atPath:)`` for callers with nowhere to throw to — a menu
    /// being rebuilt, a settings form being populated. `nil` means unreadable.
    public static func read(atPath path: String) -> String? {
        try? readOrThrow(atPath: path)
    }
}
