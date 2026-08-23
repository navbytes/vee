import Foundation

/// The menu-line parameter keys Vee recognises.
///
/// This exists so the CLI linter does not have to keep its own copy: before
/// this, `VeeCLI.Linter` carried a hand-maintained mirror of
/// `LineParser.mapParams`'s switch, and the two could (and did) drift from the
/// published reference without anything noticing.
///
/// It is still a mirror of that switch — Swift cannot enumerate a switch's
/// cases — but it is the *only* remaining one, it lives in the same module as
/// the parser, and `docs/scripts/check_params.py` fails CI when it, the
/// switch, and the authoring reference disagree.
///
/// Keys are lowercase: `LineParser` lowercases every key before dispatching, so
/// `templateImage` and `templateimage` are the same parameter.
public enum LineParameterKeys {
    /// Every key `LineParser.mapParams` handles, excluding the positional
    /// `param0…paramN` family (see `isRecognized(_:)`).
    public static let recognized: Set<String> = [
        // Rendering
        "color", "font", "size", "length", "trim", "ansi", "emojize",
        // Behavior
        "href", "shell", "bash", "terminal", "refresh", "dropdown",
        "alternate", "disabled", "key",
        // Images
        "image", "templateimage",
        // SwiftBar extensions
        "sfimage", "sfcolor", "sfsize", "sfconfig", "symbolize", "tooltip",
        "md", "markdown", "checked", "badge", "webview", "webvieww",
        "webviewh", "shortcut",
        // Vee-native
        "sparkline", "sparklinew", "sparklineh", "sparklinecolor",
        "toggle", "slider", "progress",
        // `trackcolor` is the pre-v2 spelling of `progresstrackcolor`: still
        // parsed and still recognised so existing plugins keep working, but
        // deprecated and no longer emitted by the SDKs.
        "progresstrackcolor", "trackcolor",
        "progressw", "progressh", "header", "accessory",
        "pie", "donut", "stackedbar", "chartlabels", "chartcolors",
        "chartw", "charth"
    ]

    /// Whether `key` is a parameter Vee understands. Handles the positional
    /// `param0`, `param1`, … family, which is open-ended and so cannot be a
    /// member of `recognized`.
    ///
    /// `key` is matched case-insensitively, matching `LineParser`.
    public static func isRecognized(_ key: String) -> Bool {
        let lower = key.lowercased()
        if recognized.contains(lower) { return true }
        if lower.hasPrefix("param"), Int(lower.dropFirst(5)) != nil { return true }
        return false
    }
}
