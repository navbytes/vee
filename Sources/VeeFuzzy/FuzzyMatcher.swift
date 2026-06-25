import Foundation
import VeeProtocol

/// fzy-style native fuzzy matcher — the "filter natively per keystroke" half of
/// Vee's fetch-vs-filter split (see docs/ARCHITECTURE.md §1.5).
///
/// Scoring is a Wagner–Fischer / Needleman–Wunsch-style dynamic program with an
/// **affine gap penalty** (cheap to extend a run, a one-time penalty to open a
/// gap) plus positional **bonuses** for word boundaries (start-of-word, after a
/// separator, camelCase humps) and **consecutive runs**. Higher is better. A
/// candidate must contain the query as a case-insensitive, Unicode-normalized
/// subsequence to match at all; otherwise it is excluded.
///
/// Strings are folded to `[Unicode.Scalar]` (NFC + lowercase) at ingest and
/// compared as `UInt32` for speed. The DP runs in flat, reused scratch buffers
/// so a 10k-candidate keystroke is allocation-light.
///
/// `match`/`score` are the frozen public entrypoints. For per-keystroke use the
/// host should build `[PreparedCandidate]` once at ingest (`prepare`) and call
/// `match(query:inPrepared:)` — that hoists all normalization and word-boundary
/// masking out of the hot path.
public enum FuzzyMatcher {

    // MARK: - Public API (frozen signatures)

    /// Score and rank `candidates` against `query`, descending. Non-matches are
    /// excluded. An empty query returns **all** candidates in input order, score 0.
    public static func match(query: String, in candidates: [Candidate]) -> [ScoredCandidate] {
        if query.isEmpty {
            return candidates.map { ScoredCandidate(candidate: $0, score: 0, matchedIndices: []) }
        }
        let prepared = candidates.map { PreparedCandidate($0) }
        return match(query: query, inPrepared: prepared)
    }

    /// Score a single candidate against `query`; `nil` when it doesn't match.
    /// Empty query yields a neutral `0`.
    public static func score(query: String, candidate: Candidate) -> Double? {
        if query.isEmpty { return 0 }
        let q = QueryKey(query)
        if q.isEmpty { return 0 }
        let scratch = Scratch()
        return PreparedCandidate(candidate).bestScore(for: q, scratch: scratch)?.score
    }

    // MARK: - Precomputed (instance) API for the per-keystroke hot path

    /// Rank a pre-ingested candidate set. Empty query returns all in input order.
    /// Distinct argument label (`inPrepared:`) so an empty array literal never
    /// makes a `match(query:in:)` call ambiguous against the `[Candidate]` overload.
    public static func match(query: String, inPrepared prepared: [PreparedCandidate]) -> [ScoredCandidate] {
        if query.isEmpty {
            return prepared.map { ScoredCandidate(candidate: $0.candidate, score: 0, matchedIndices: []) }
        }
        let q = QueryKey(query)
        if q.isEmpty {
            return prepared.map { ScoredCandidate(candidate: $0.candidate, score: 0, matchedIndices: []) }
        }

        // One reused scratch for the whole pass keeps allocations out of the loop.
        let scratch = Scratch()
        var scored: ContiguousArray<ScoredCandidate> = []
        scored.reserveCapacity(prepared.count)
        for idx in prepared.indices {
            guard let r = prepared[idx].bestScore(for: q, scratch: scratch) else { continue }
            scored.append(ScoredCandidate(candidate: prepared[idx].candidate,
                                          score: r.score,
                                          matchedIndices: r.indices))
        }
        // Descending by score; the sort is stable enough for our needs and ties are
        // rare (distinct scores dominate); keep it simple and fast.
        scored.sort { $0.score > $1.score }
        return Array(scored)
    }

    /// Precompute the folded match strings + word-boundary masks for a candidate
    /// set so per-keystroke scoring is pure DP.
    public static func prepare(_ candidates: [Candidate]) -> [PreparedCandidate] {
        candidates.map { PreparedCandidate($0) }
    }
}

// MARK: - Scoring constants (fzy-inspired)

enum Score {
    static let max = Double.greatestFiniteMagnitude
    static let min = -Double.greatestFiniteMagnitude

    /// Affine gap: one-time cost to *open* a gap, smaller cost to *extend* it.
    static let gapLeading: Double = -0.005      // gap before the first match
    static let gapTrailing: Double = -0.005     // gap after the last match
    static let gapInner: Double = -0.01         // gap between two matched chars

    /// Bonuses (added when a matched char sits at a salient position).
    static let matchConsecutive: Double = 1.0   // immediately follows a prior match
    static let boundarySlash: Double = 0.9       // after '/'
    static let boundaryWord: Double = 0.8        // after a separator (space, _, -, .)
    static let boundaryCamel: Double = 0.7       // lower→Upper camelCase hump
    static let firstChar: Double = 0.85          // very first scalar of the string
}

// MARK: - Normalization

enum Normalize {
    /// Canonical (NFC) + case fold, as a scalar array. Combining marks are folded
    /// into precomposed forms where possible; stray marks survive (and don't crash).
    static func foldedScalars(_ s: String) -> [Unicode.Scalar] {
        Array(s.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars)
    }
}

// MARK: - Query key (normalized once)

/// A query normalized for matching: NFC + lowercased, as a scalar array.
public struct QueryKey: Sendable {
    let scalars: [UInt32]
    init(_ s: String) {
        scalars = Normalize.foldedScalars(s).map { $0.value }
    }
    var isEmpty: Bool { scalars.isEmpty }
    var count: Int { scalars.count }
}

// MARK: - One matchable field (title or a keyword), precomputed.

struct MatchField: Sendable {
    /// Folded scalar code points of the field (compared as UInt32).
    let scalars: [UInt32]
    /// Per-position bonus the scalar *would* earn as a non-consecutive match
    /// (word-boundary / first-char / slash). Length == scalars.count.
    let bonus: [Double]

    init(_ raw: String) {
        let folded = Normalize.foldedScalars(raw)
        scalars = folded.map { $0.value }

        // Detect boundaries from the canonical (NFC) but pre-lowercase scalars so
        // camelCase humps survive (lowercasing would erase them).
        let canonical = Array(raw.precomposedStringWithCanonicalMapping.unicodeScalars)
        let n = folded.count
        var b = [Double](repeating: 0, count: n)
        var prev: Unicode.Scalar? = nil
        for i in 0..<n {
            let cur = i < canonical.count ? canonical[i] : folded[i]
            var bonus: Double = 0
            if i == 0 {
                bonus = Score.firstChar
            } else if let p = prev {
                if p == "/" {
                    bonus = Score.boundarySlash
                } else if p == " " || p == "_" || p == "-" || p == "." {
                    bonus = Score.boundaryWord
                } else {
                    let pProps = p.properties
                    let cProps = cur.properties
                    if pProps.isLowercase && cProps.isUppercase {
                        bonus = Score.boundaryCamel
                    } else if !CharacterSet.decimalDigits.contains(p) && CharacterSet.decimalDigits.contains(cur) {
                        bonus = Score.boundaryCamel
                    }
                }
            }
            b[i] = bonus
            prev = cur
        }
        bonus = b
    }
}

// MARK: - Prepared candidate (title + keywords precomputed)

/// A `Candidate` with its title and keywords folded + boundary-masked once, so
/// per-keystroke scoring is pure DP. Build with `FuzzyMatcher.prepare`.
public struct PreparedCandidate: Sendable {
    public let candidate: Candidate
    let title: MatchField
    let keywords: [MatchField]

    public init(_ candidate: Candidate) {
        self.candidate = candidate
        self.title = MatchField(candidate.title)
        self.keywords = candidate.keywords.map { MatchField($0) }
    }

    struct Result { var score: Double; var indices: [Int] }

    /// Best score across title + keywords. Reports matched indices from the title
    /// when the title matches (so highlight lines up with displayed text); a
    /// keyword-only win still scores but returns empty indices (the host
    /// highlights the title, and keyword indices don't address it).
    func bestScore(for q: QueryKey, scratch: Scratch) -> Result? {
        var best: Double = Score.min
        var bestIndices: [Int] = []
        var matched = false

        if let titleScore = scratch.score(query: q.scalars, field: title, needIndices: true) {
            matched = true
            best = titleScore.score
            bestIndices = titleScore.indices
        }

        for kw in keywords {
            // Keyword score doesn't need a traceback (indices wouldn't address the
            // title), so skip the index reconstruction for speed.
            guard let s = scratch.score(query: q.scalars, field: kw, needIndices: false) else { continue }
            matched = true
            if s.score > best {
                best = s.score
                bestIndices = []   // keyword win → no title-relative highlight
            }
        }

        guard matched else { return nil }
        return Result(score: best, indices: bestIndices)
    }
}

// MARK: - The DP scorer (flat, reused buffers)

/// Reusable scratch for the DP. Buffers grow on demand and are reused across all
/// candidates in a single `match` pass, keeping the hot path allocation-light.
final class Scratch {
    private var d: [Double] = []   // flattened n×m
    private var m: [Double] = []   // flattened n×m
    private var capacity = 0

    struct Scored { var score: Double; var indices: [Int] }

    /// fzy-style scoring of `query` against a single field. Returns nil if
    /// `query` is not a subsequence of the field. Higher score == better.
    /// When `needIndices` is false, skips the traceback (caller only wants score).
    func score(query: [UInt32], field: MatchField, needIndices: Bool) -> Scored? {
        let text = field.scalars
        let n = query.count
        let mm = text.count
        if n == 0 { return Scored(score: 0, indices: []) }
        if n > mm { return nil }

        // Fast subsequence check (also rejects most candidates cheaply).
        if !Scratch.isSubsequence(query, of: text) { return nil }

        // Exact full-string equality → maximum score, so an exact match always
        // outranks any strictly-longer subsequence host.
        if n == mm {
            return Scored(score: Score.max, indices: needIndices ? Array(0..<n) : [])
        }

        let needed = n * mm
        if needed > capacity {
            capacity = needed
            d = [Double](repeating: 0, count: needed)
            m = [Double](repeating: 0, count: needed)
        }

        return query.withUnsafeBufferPointer { q in
            text.withUnsafeBufferPointer { t in
                field.bonus.withUnsafeBufferPointer { bonus in
                    d.withUnsafeMutableBufferPointer { D in
                        m.withUnsafeMutableBufferPointer { M in
                            Scratch.runDP(q: q, t: t, bonus: bonus, D: D, M: M,
                                          n: n, mm: mm, needIndices: needIndices)
                        }
                    }
                }
            }
        }
    }

    @inline(__always)
    private static func runDP(q: UnsafeBufferPointer<UInt32>,
                              t: UnsafeBufferPointer<UInt32>,
                              bonus: UnsafeBufferPointer<Double>,
                              D: UnsafeMutableBufferPointer<Double>,
                              M: UnsafeMutableBufferPointer<Double>,
                              n: Int, mm: Int, needIndices: Bool) -> Scored? {
        // D[i*mm + j] = best score for matching query[0...i] with query[i] at text[j].
        // M[i*mm + j] = best score for matching query[0...i] using text[0...j].
        for i in 0..<n {
            let qc = q[i]
            let rowBase = i * mm
            let prevBase = rowBase - mm
            let gapPenalty = (i == n - 1) ? Score.gapTrailing : Score.gapInner
            var prevM = Score.min   // M[i][j-1]

            for j in 0..<mm {
                if qc == t[j] {
                    var scoreHere: Double
                    if i == 0 {
                        scoreHere = Double(j) * Score.gapLeading + bonus[j]
                    } else if j > 0 {
                        let consecutive = D[prevBase + j - 1] + Score.matchConsecutive
                        let gapped = M[prevBase + j - 1] + bonus[j]
                        scoreHere = consecutive > gapped ? consecutive : gapped
                    } else {
                        scoreHere = Score.min   // can't place query[i>0] at text[0]
                    }
                    D[rowBase + j] = scoreHere
                    let extend = (prevM == Score.min) ? Score.min : prevM + gapPenalty
                    prevM = scoreHere > extend ? scoreHere : extend
                    M[rowBase + j] = prevM
                } else {
                    D[rowBase + j] = Score.min
                    prevM = (prevM == Score.min) ? Score.min : prevM + gapPenalty
                    M[rowBase + j] = prevM
                }
            }
        }

        // Best end position is the last row's max of M.
        let lastBase = (n - 1) * mm
        var bestJ = 0
        var bestScore = Score.min
        for j in 0..<mm {
            let v = M[lastBase + j]
            if v > bestScore { bestScore = v; bestJ = j }
        }
        if bestScore == Score.min { return nil }

        guard needIndices else { return Scored(score: bestScore, indices: []) }

        // Traceback through D.
        var indices = [Int](repeating: 0, count: n)
        var i = n - 1
        var j = bestJ
        // Snap to the matched cell on the last row (M may have ridden a trailing gap).
        while j >= 0 && D[i * mm + j] != M[i * mm + j] { j -= 1 }
        while i >= 0 {
            indices[i] = j
            if i == 0 { break }
            let consecutive = (j > 0) ? D[(i - 1) * mm + j - 1] + Score.matchConsecutive : Score.min
            if j > 0 && D[i * mm + j] == consecutive {
                i -= 1; j -= 1
            } else {
                i -= 1; j -= 1
                while j >= 0 && D[i * mm + j] != M[i * mm + j] { j -= 1 }
            }
        }
        return Scored(score: bestScore, indices: indices)
    }

    @inline(__always)
    static func isSubsequence(_ query: [UInt32], of text: [UInt32]) -> Bool {
        let n = query.count
        if n == 0 { return true }
        var qi = 0
        let target0 = query[0]
        var next = target0
        for c in text {
            if c == next {
                qi += 1
                if qi == n { return true }
                next = query[qi]
            }
        }
        return false
    }
}
