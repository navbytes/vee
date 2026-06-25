import Foundation
import VeeProtocol
import VeeFuzzy

// MARK: - Seam: app enumeration

/// A value record for one discovered application. The only thing that crosses
/// the enumeration seam — no `NSWorkspace`/Launch Services types leak up.
public struct AppRecord: Hashable, Sendable {
    public var name: String
    public var bundleId: String
    public var path: String
    public init(name: String, bundleId: String, path: String) {
        self.name = name
        self.bundleId = bundleId
        self.path = path
    }
}

/// The OS seam over Launch Services / `/Applications` scanning. The fake (tests)
/// and a thin real adapter both conform; dedup + ranking live ABOVE this seam.
public protocol AppEnumerating: AnyObject {
    func enumerateApps() -> [AppRecord]
}

// MARK: - Frecency

/// Frequency × recency scoring with exponential decay. Each launch contributes a
/// weight of `0.5 ^ (age / halfLife)` — a launch's value halves every `halfLife`
/// seconds (~30 days by default). Summing over the launch log rewards both
/// frequent and recent use. Pure over an injected clock + a launch log, so it is
/// deterministic in tests.
struct FrecencyModel {
    /// ~30-day half-life in seconds.
    var halfLife: TimeInterval = 60 * 60 * 24 * 30

    /// Launch timestamps per bundleId (the launch log).
    private var launches: [String: [Date]] = [:]

    mutating func record(bundleId: String, at time: Date) {
        launches[bundleId, default: []].append(time)
    }

    /// Decayed frecency for a bundleId as of `now`. 0 when never launched.
    func score(bundleId: String, now: Date) -> Double {
        guard let stamps = launches[bundleId], !stamps.isEmpty else { return 0 }
        var total = 0.0
        for t in stamps {
            let age = max(0, now.timeIntervalSince(t))
            total += pow(0.5, age / halfLife)
        }
        return total
    }
}

// MARK: - App search provider

/// Enumerates apps over the `AppEnumerating` seam, dedups by bundleId across
/// roots, and ranks by a weighted blend of `VeeFuzzy` score + frecency. Returns
/// `[Candidate]` for the shared native-filter pipeline.
///
/// Ranking is fully above the seam and deterministic given an injected clock +
/// launch log, so case 8/9 assert exact ordering.
///
/// Thread-safety: production calls `recordLaunch` on the main thread while
/// `search` runs on a background queue (see `vee-plugin-host/main.swift`). The
/// mutable frecency state (a `Dictionary` that `record` mutates and `score`
/// iterates) is therefore guarded by an `NSLock`, mirroring
/// `VeeKeychain.InMemorySecretStore`. Every read/write of `frecency` happens
/// while the lock is held, so it is safe to use the provider from any queue.
/// `@unchecked Sendable` because the only mutable state is the lock-protected
/// `frecency`; everything else is immutable after `init`.
public final class AppSearchProvider: @unchecked Sendable {
    private let enumerator: AppEnumerating
    private let clock: Clock

    /// Lock guarding `frecency`. Held for the (short) duration of each record
    /// and each score read; never held across a call back into JS or the seam.
    private let frecencyLock = NSLock()
    private var frecency = FrecencyModel()

    /// Blend weights. Fuzzy dominates the base relevance; frecency is a tie/near-
    /// tie breaker. An exact prefix gets an explicit, large additive bonus so it
    /// always outranks a mid-word subsequence regardless of frecency.
    private let fuzzyWeight: Double
    private let frecencyWeight: Double
    private let prefixBonus: Double

    public init(enumerator: AppEnumerating,
                clock: Clock,
                fuzzyWeight: Double = 1.0,
                frecencyWeight: Double = 2.0,
                prefixBonus: Double = 1_000.0) {
        self.enumerator = enumerator
        self.clock = clock
        self.fuzzyWeight = fuzzyWeight
        self.frecencyWeight = frecencyWeight
        self.prefixBonus = prefixBonus
    }

    /// Record an app launch (frequency × recency input). Production calls this
    /// when the user actually opens an app (main thread), concurrently with
    /// `search` on a background queue — so the mutation is lock-guarded.
    public func recordLaunch(bundleId: String) {
        frecencyLock.lock(); defer { frecencyLock.unlock() }
        frecency.record(bundleId: bundleId, at: clock.now)
    }

    /// Lock-guarded frecency read. A tiny helper so every `score` access goes
    /// through the lock without re-entrancy or holding it across other work.
    private func frecencyScore(bundleId: String, now: Date) -> Double {
        frecencyLock.lock(); defer { frecencyLock.unlock() }
        return frecency.score(bundleId: bundleId, now: now)
    }

    /// Deduplicated app set: first occurrence of each bundle id wins, then a
    /// second pass collapses duplicate display names (e.g. an app present in both
    /// `/Applications` and a web-app shortcut) so the launcher never shows two
    /// identical rows.
    private func dedupedApps() -> [AppRecord] {
        var seenIds = Set<String>()
        var seenNames = Set<String>()
        var out: [AppRecord] = []
        for app in enumerator.enumerateApps() {
            guard seenIds.insert(app.bundleId).inserted else { continue }
            guard seenNames.insert(app.name.lowercased()).inserted else { continue }
            out.append(app)
        }
        return out
    }

    /// Map an `AppRecord` to a `Candidate` (id == bundleId, so dedup is by id too).
    private func candidate(for app: AppRecord) -> Candidate {
        Candidate(id: app.bundleId,
                  title: app.name,
                  subtitle: nil,
                  icon: app.path,
                  actions: [CandidateAction(id: "launch", title: "Launch")])
    }

    /// Search + rank. Empty query returns the deduped set ranked by frecency
    /// (newest/most-used first), capped at `limit`. Non-empty query fuzzy-filters
    /// then blends in frecency + the exact-prefix bonus.
    public func search(query: String, limit: Int) -> [Candidate] {
        let now = clock.now
        let apps = dedupedApps()
        let cap = max(0, limit)

        if query.isEmpty {
            // Stable-rank by frecency desc, then name for determinism.
            let ranked = apps.sorted { a, b in
                let fa = frecencyScore(bundleId: a.bundleId, now: now)
                let fb = frecencyScore(bundleId: b.bundleId, now: now)
                if fa != fb { return fa > fb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return Array(ranked.prefix(cap).map(candidate(for:)))
        }

        let q = query.lowercased()
        var scored: [(candidate: Candidate, score: Double)] = []
        for app in apps {
            let cand = candidate(for: app)
            guard let fuzzy = FuzzyMatcher.score(query: query, candidate: cand) else { continue }
            var blended = fuzzyWeight * fuzzy
                + frecencyWeight * frecencyScore(bundleId: app.bundleId, now: now)
            if app.name.lowercased().hasPrefix(q) {
                blended += prefixBonus
            }
            scored.append((cand, blended))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.candidate.title.localizedCaseInsensitiveCompare(rhs.candidate.title) == .orderedAscending
        }
        return Array(scored.prefix(cap).map(\.candidate))
    }
}
