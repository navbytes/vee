import Foundation

/// A list item / candidate fed into the native fuzzy pipeline.
///
/// The plugin pushes `[Candidate]` once per open/refresh (`plugin.setCandidates`);
/// the host filters them per keystroke with `VeeFuzzy` and never crosses IPC on
/// a keypress. `keywords` augment the title for matching (e.g. acronyms);
/// `actions` enumerate what the user can do, each carrying an `actionId` the
/// host echoes back via `host.invokeAction`.
public struct Candidate: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity; used to diff candidate sets in place (preserve selection).
    public var id: String
    public var title: String
    public var subtitle: String?
    /// Optional icon hint (SF Symbol name, file path, or URL — host decides).
    public var icon: String?
    /// Extra match terms beyond `title` (acronyms, tags, repo names…).
    public var keywords: [String]
    public var actions: [CandidateAction]

    public init(id: String,
                title: String,
                subtitle: String? = nil,
                icon: String? = nil,
                keywords: [String] = [],
                actions: [CandidateAction] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.icon = icon; self.keywords = keywords; self.actions = actions
    }
}

public struct CandidateAction: Codable, Hashable, Identifiable, Sendable {
    /// Echoed back to the plugin via `host.invokeAction`.
    public var id: String
    public var title: String
    /// Optional shortcut hint, e.g. "cmd+enter". Host renders/binds if able.
    public var shortcut: String?
    public init(id: String, title: String, shortcut: String? = nil) {
        self.id = id; self.title = title; self.shortcut = shortcut
    }
}

/// The result of scoring a candidate against a query, produced by `VeeFuzzy`.
/// Carries the match positions so the host can highlight matched characters.
public struct ScoredCandidate: Hashable, Sendable {
    public var candidate: Candidate
    public var score: Double
    /// Indices into the matched string where query chars landed (for highlight).
    public var matchedIndices: [Int]
    public init(candidate: Candidate, score: Double, matchedIndices: [Int] = []) {
        self.candidate = candidate; self.score = score; self.matchedIndices = matchedIndices
    }
}
