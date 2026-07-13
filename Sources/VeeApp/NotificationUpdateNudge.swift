import Foundation
import VeeCatalog

/// Persists the (plugin, version) pairs the user has already been notified
/// about, so a catalog scan doesn't nudge again for the same update every
/// time it runs — a *different*, newer version for the same plugin is still
/// free to notify. Backed by `UserDefaults`, matching `AppPreferences` /
/// `StoreRegistry` (small, app-wide state) rather than the on-disk ledger
/// convention `ProvenanceStore` / `CatalogFreshnessStore` use — this isn't
/// tied to any one plugins directory.
/// `@unchecked Sendable`: `UserDefaults` is thread-safe.
struct UpdateNotificationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "vee.notifiedPluginUpdates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last version token notified for each filename.
    private func notified() -> [String: String] {
        (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }

    /// Whether `candidate`'s exact (plugin, version) pair was already surfaced.
    func hasNotified(_ candidate: PluginUpdateCandidate) -> Bool {
        notified()[candidate.filename] == candidate.versionToken
    }

    /// Records `candidates` as surfaced, so a repeat scan for the same
    /// versions doesn't nudge again.
    func markNotified(_ candidates: [PluginUpdateCandidate]) {
        guard !candidates.isEmpty else { return }
        var current = notified()
        for candidate in candidates { current[candidate.filename] = candidate.versionToken }
        defaults.set(current, forKey: Self.key)
    }
}

/// The coalesced notification body for a catalog-update nudge — always one
/// line regardless of how many plugins changed, per the "post one
/// notification, not one per plugin" rule.
enum CatalogUpdateNudgeText {
    static func body(for filenames: [String]) -> String {
        let sorted = filenames.sorted()
        guard let first = sorted.first else { return "" }
        if sorted.count == 1 { return "\(first) has an update available." }
        return "\(sorted.count) plugin updates available: \(sorted.joined(separator: ", "))."
    }
}
