import Foundation

/// A small fuzzy subsequence scorer in the fzf/Sublime tradition: a query token
/// matches a string iff its characters appear in order (not necessarily
/// adjacent), and the score rewards matches that are contiguous, at word
/// boundaries, and near the start. Greedy left-to-right — deterministic and
/// "good enough" ranking, not an optimal-alignment search.
///
/// Inputs are expected pre-folded by `SearchText.fold` (lowercased, diacritic-
/// and width-insensitive), so comparison is plain `Character` equality.
enum FuzzyScorer {
    static let prefixBonus = 20         // token starts at index 0
    static let boundaryBonus = 25       // matched char sits at a word boundary
    static let sequentialBonus = 15     // matched char is adjacent to the prior match
    static let leadingGapCap = 15       // cap on the "how far in the first match is" penalty
    static let gapPenalty = 1           // per non-adjacent character within the matched span

    /// Characters that begin a new "word" for the boundary bonus.
    static let separators: Set<Character> = [
        " ", "\t", "\n", "›", ">", "/", "\\", "-", "_", ".", ":",
        "|", ",", ";", "(", ")", "[", "]", "{", "}", "#", "@", "="
    ]

    /// Returns a match score (higher is better) or `nil` when `query` is not a
    /// subsequence of `text`. An empty query scores 0 (matches everything).
    static func score(query: String, in text: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query)
        let t = Array(text)

        var qi = 0
        var score = 0
        var firstMatch: Int?
        var prevMatch: Int?

        var i = 0
        while i < t.count && qi < q.count {
            if t[i] == q[qi] {
                if firstMatch == nil { firstMatch = i }
                let atBoundary = (i == 0) || separators.contains(t[i - 1])
                if atBoundary { score += boundaryBonus }
                if let pm = prevMatch, pm == i - 1 { score += sequentialBonus }
                prevMatch = i
                qi += 1
            }
            i += 1
        }

        guard qi == q.count else { return nil }   // not all query chars consumed → no match

        if firstMatch == 0 { score += prefixBonus }
        if let fm = firstMatch { score -= min(fm, leadingGapCap) }        // earlier is better
        if let fm = firstMatch, let pm = prevMatch {                      // compact is better
            let gaps = (pm - fm + 1) - q.count
            score -= gaps * gapPenalty
        }
        return score
    }
}
