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
}

/// Production wrapper over `VeeFuzzy.FuzzyMatcher`. For larger sets it could hold
/// a `[PreparedCandidate]` cache; the coordinator re-prepares on `setCandidates`,
/// which is the once-per-open/refresh boundary, so per-keystroke work stays in
/// the matcher's reused scratch buffers.
public final class LiveFuzzyMatcher: FuzzyMatching {
    public init() {}
    public func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        FuzzyMatcher.match(query: query, in: candidates)
    }
}
