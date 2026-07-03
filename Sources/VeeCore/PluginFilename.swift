import Foundation

/// A parsed plugin filename of the form `{name}.{interval?}.{ext?}`.
///
/// Examples:
/// - `cpu.10s.sh`     → name `cpu`, interval `.seconds(10)`, ext `sh`
/// - `my.plugin.5m.py`→ name `my.plugin`, interval `.minutes(5)`, ext `py`
/// - `weather.sh`     → name `weather`, interval `.manual`, ext `sh`
/// - `notes`          → name `notes`, interval `.manual`, ext `""`
///
/// The interval token is recognised only when it sits immediately before the
/// extension and there is a non-empty name in front of it, so `10s.sh` parses
/// as name `10s` (manual), not an anonymous 10-second plugin.
public struct PluginFilename: Equatable, Sendable {
    public let name: String
    public let interval: RefreshInterval
    public let ext: String

    public init(name: String, interval: RefreshInterval, ext: String) {
        self.name = name
        self.interval = interval
        self.ext = ext
    }

    public init(_ filename: String) {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        // Single component: bare name, no extension.
        guard parts.count >= 2 else {
            self.init(name: filename, interval: .manual, ext: "")
            return
        }

        let ext = parts[parts.count - 1]
        let maybeToken = parts[parts.count - 2]

        // An interval token counts only if there is a name before it.
        if parts.count >= 3, let interval = RefreshInterval.parse(token: maybeToken) {
            let name = parts[0..<(parts.count - 2)].joined(separator: ".")
            self.init(name: name, interval: interval, ext: ext)
        } else {
            let name = parts[0..<(parts.count - 1)].joined(separator: ".")
            self.init(name: name, interval: .manual, ext: ext)
        }
    }
}
