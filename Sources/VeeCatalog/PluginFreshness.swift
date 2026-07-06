import Foundation

/// How recently a catalog plugin was last updated upstream, used to tint a
/// freshness badge on its card. Pure and unit-testable — classification takes
/// `now` as a parameter so it never reads the clock implicitly.
public enum PluginFreshness: Sendable, Equatable {
    /// Updated within the last 6 months.
    case fresh
    /// Updated between 6 months and 2 years ago.
    case aging
    /// Not updated in over 2 years.
    case stale

    private static let sixMonths: TimeInterval = 60 * 60 * 24 * 365 / 2
    private static let twoYears: TimeInterval = 60 * 60 * 24 * 365 * 2

    /// Classifies a plugin's freshness from its last-updated date relative to
    /// `now`. Returns `nil` when the date is unknown (not yet fetched), so
    /// callers render nothing rather than guessing.
    ///
    /// - Parameters:
    ///   - lastUpdated: The last upstream commit date, or `nil` if unknown.
    ///   - now: The reference "now" — injected for deterministic tests.
    public static func classify(lastUpdated: Date?, now: Date) -> PluginFreshness? {
        guard let lastUpdated else { return nil }
        let age = now.timeIntervalSince(lastUpdated)
        if age < sixMonths { return .fresh }
        if age < twoYears { return .aging }
        return .stale
    }
}
