import Foundation
import VeeProtocol
import VeeFuzzy

/// The per-keystroke filter seam. The coordinator owns the candidate set pushed
/// by the plugin (`plugin.setCandidates`) and filters it natively on every
/// keystroke through this wrapper — never crossing IPC (docs/ARCHITECTURE.md §5,
/// the fetch-once/filter-natively split). Injected so the query→filter test can
/// use a deterministic stub instead of the real scoring algorithm.
public protocol FuzzyMatching: AnyObject {
    /// Score + rank `candidates` against `query`, best first; non-matches
    /// excluded. An empty query returns all candidates in input order.
    func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate]

    /// PERF-2 hot-path API: fold + boundary-mask the candidate set ONCE (on
    /// `setCandidates`/`showHostCandidates`), then score the prepared set per
    /// keystroke without re-normalizing. The coordinator caches the result.
    func prepare(_ candidates: [Candidate]) -> [PreparedCandidate]
    /// Score + rank a pre-prepared candidate set against `query`.
    func match(query: String, inPrepared prepared: [PreparedCandidate]) -> [ScoredCandidate]
}

public extension FuzzyMatching {
    /// Default: wrap each candidate. Production (`LiveFuzzyMatcher`) overrides to
    /// use the real folded/boundary-masked preparation.
    func prepare(_ candidates: [Candidate]) -> [PreparedCandidate] {
        candidates.map { PreparedCandidate($0) }
    }
    /// Default: recover the underlying candidates and delegate to the plain
    /// matcher — so a test double that only overrides `match(query:in:)` keeps
    /// working without implementing the prepared path.
    func match(query: String, inPrepared prepared: [PreparedCandidate]) -> [ScoredCandidate] {
        match(query: query, in: prepared.map(\.candidate))
    }
}

/// Production wrapper over `VeeFuzzy.FuzzyMatcher`. The coordinator caches the
/// `[PreparedCandidate]` from `prepare(_:)` at the once-per-open/refresh boundary
/// and calls `match(query:inPrepared:)` per keystroke, so each keypress is pure
/// DP over pre-folded fields (PERF-2) with the matcher's reused scratch buffers.
public final class LiveFuzzyMatcher: FuzzyMatching {
    public init() {}
    public func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        FuzzyMatcher.match(query: query, in: candidates)
    }
    public func prepare(_ candidates: [Candidate]) -> [PreparedCandidate] {
        FuzzyMatcher.prepare(candidates)
    }
    public func match(query: String, inPrepared prepared: [PreparedCandidate]) -> [ScoredCandidate] {
        FuzzyMatcher.match(query: query, inPrepared: prepared)
    }
}
