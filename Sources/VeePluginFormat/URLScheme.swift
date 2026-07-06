import Foundation

/// Scheme policy for URLs that come from untrusted plugin output (`href=`,
/// `webview=`, `swiftbar://addplugin?src=`). Plugins run un-sandboxed, but a
/// single *click* opening a URL shouldn't silently reach local files or inject
/// script, so Vee filters schemes before opening/loading.
public enum URLScheme {
    /// Schemes that must never be opened from a plugin `href=`. `file`/`data` can
    /// read or embed local content; `javascript`/`vbscript` inject script; `blob`
    /// references in-process data. Everything else (http/https/mailto and custom
    /// app deep links like `shortcuts:`) is allowed, preserving compatibility.
    private static let blockedForHref: Set<String> = ["file", "javascript", "vbscript", "data", "blob"]

    /// `webview=` and remote plugin fetches load/execute content in-app, so they
    /// are restricted to real web schemes only.
    private static let allowedForWeb: Set<String> = ["http", "https"]

    /// True when `url` is safe to hand to `NSWorkspace.open` from plugin output.
    public static func isSafeToOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !blockedForHref.contains(scheme)
    }

    /// True when `url` is a real web URL (for `webview=` and remote fetches).
    public static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedForWeb.contains(scheme)
    }
}
