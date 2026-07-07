import Foundation
import VeePluginFormat

/// The public entry point for the searchable-menu core: flatten a plugin's menu
/// tree, then filter + rank it by a typed query. Pure and AppKit-free — the UI
/// layer owns presentation; all matching logic lives (and is tested) here.
public enum MenuSearch {
    /// Extra weight for a token that matches the item's own text rather than only
    /// an ancestor (breadcrumb) title, so direct hits outrank contextual ones.
    static let titleMatchBonus = 40

    /// Flattens a `ParsedOutput.body` into activatable rows (breadcrumb-aware).
    public static func flatten(_ nodes: [MenuNode]) -> [FlatRow] {
        MenuFlattener.flatten(nodes)
    }

    /// Filters and ranks `rows` for `query`. An empty/whitespace query is the idle
    /// state: every row, in original order. Otherwise a row is kept iff **every**
    /// whitespace-separated token fuzzy-matches (multi-token AND), ranked by score
    /// descending with original order as a stable tie-break.
    public static func search(_ query: String, in rows: [FlatRow]) -> [FlatRow] {
        scored(query, in: rows).map(\.row)
    }

    /// Like `search`, but returns the per-row scores (for tests / debugging).
    public static func scored(_ query: String, in rows: [FlatRow]) -> [ScoredRow] {
        let tokens = SearchText.tokens(SearchText.fold(query))
        guard !tokens.isEmpty else {
            return rows.map { ScoredRow(row: $0, score: 0) }   // idle: all, original order
        }

        var matched: [(index: Int, scored: ScoredRow)] = []
        for (index, row) in rows.enumerated() {
            if let total = rowScore(tokens: tokens, row: row) {
                matched.append((index, ScoredRow(row: row, score: total)))
            }
        }
        return matched
            .sorted { $0.scored.score != $1.scored.score ? $0.scored.score > $1.scored.score : $0.index < $1.index }
            .map(\.scored)
    }

    /// Sum of per-token scores, or `nil` if any token fails to match (AND).
    private static func rowScore(tokens: [String], row: FlatRow) -> Int? {
        var total = 0
        for token in tokens {
            guard let s = tokenScore(token, row: row) else { return nil }
            total += s
        }
        return total
    }

    /// A token prefers to match the item text (with a bonus); failing that it may
    /// match the fuller haystack (item text + ancestors) so a breadcrumb hit still
    /// surfaces the row, but ranks below a direct title hit.
    private static func tokenScore(_ token: String, row: FlatRow) -> Int? {
        if let s = FuzzyScorer.score(query: token, in: row.title) {
            return s + titleMatchBonus
        }
        if let s = FuzzyScorer.score(query: token, in: row.haystack) {
            return s
        }
        return nil
    }
}
