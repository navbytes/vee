import Foundation

/// How often a plugin is re-run. Encoded in the plugin's filename
/// (`name.{N}{unit}.ext`, e.g. `cpu.10s.sh`) or overridden by a
/// `<swiftbar.schedule>` cron header.
public enum RefreshInterval: Equatable, Sendable {
    /// No interval token in the filename — run once / on demand only.
    case manual
    case milliseconds(Int)
    case seconds(Int)
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// A raw cron expression from `<swiftbar.schedule>`. Parsed by the scheduler.
    case cron(String)

    /// The interval as a `TimeInterval`, or `nil` for `.manual`/`.cron`
    /// (which have no single fixed period).
    public var timeInterval: TimeInterval? {
        switch self {
        case .manual, .cron: return nil
        case .milliseconds(let n): return Double(n) / 1000.0
        case .seconds(let n): return Double(n)
        case .minutes(let n): return Double(n) * 60
        case .hours(let n): return Double(n) * 3600
        case .days(let n): return Double(n) * 86_400
        }
    }

    /// Parses an xbar/SwiftBar interval token such as `10s`, `1m`, `500ms`,
    /// `2h`, `1d`. Returns `nil` if the token is not a valid interval.
    ///
    /// Note: `ms` is checked before `m` so `500ms` is milliseconds, not minutes.
    public static func parse(token: String) -> RefreshInterval? {
        guard !token.isEmpty else { return nil }
        // Split into leading digits and a trailing unit.
        let digits = token.prefix { $0.isNumber }
        // A zero interval (`0s`, `0ms`, …) would arm a repeating timer that
        // refires continuously and pegs a core; reject it here so callers fall
        // back to the no-interval/manual path instead (see PluginFilename).
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        let unit = token.dropFirst(digits.count)
        switch unit {
        case "ms": return .milliseconds(value)
        case "s": return .seconds(value)
        case "m": return .minutes(value)
        case "h": return .hours(value)
        case "d": return .days(value)
        default: return nil
        }
    }
}
