import Foundation
import VeeProtocol

/// fzy-style native fuzzy matcher (the "filter natively per keystroke" half of
/// the fetch-vs-filter split).
///
/// > Wave 1a worker: implement the DP scorer (affine gap penalty, word-boundary
/// > bonus, consecutive-run bonus) + ranking + ingest precompute per build
/// > plan §4. Keep `match`/`score` as the public entrypoints; an internal
/// > precomputed-candidate instance API is fine. Tests first.
public enum FuzzyMatcher {
    /// Score and rank `candidates` against `query`. An empty query returns all
    /// candidates in input order. Non-matching candidates are excluded.
    public static func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        // Wave 0 stub: returns all candidates unranked so the skeleton compiles.
        candidates.map { ScoredCandidate(candidate: $0, score: 0, matchedIndices: []) }
    }

    /// Score a single candidate against `query`; returns nil when it doesn't match.
    public static func score(query: String, candidate: Candidate) -> Double? {
        query.isEmpty ? 0 : nil
    }
}
