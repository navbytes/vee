import XCTest
@testable import VeeFuzzy
import VeeProtocol

/// Real TDD suite for the fzy-style native fuzzy matcher (build plan §4).
/// 10 cases, written failing-first against the frozen `FuzzyMatcher` entrypoints.
final class VeeFuzzyTests: XCTestCase {

    // MARK: - Helpers

    /// Build a title-only candidate. `id` defaults to the title.
    private func cand(_ title: String, keywords: [String] = [], id: String? = nil) -> Candidate {
        Candidate(id: id ?? title, title: title, keywords: keywords)
    }

    private func titles(_ scored: [ScoredCandidate]) -> [String] {
        scored.map { $0.candidate.title }
    }

    // MARK: - 1. Empty query → all candidates, stable input order, no crash.

    func testEmptyQueryReturnsAllInInputOrder() {
        let input = [cand("Banana"), cand("Apple"), cand("Cherry")]
        let result = FuzzyMatcher.match(query: "", in: input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(titles(result), ["Banana", "Apple", "Cherry"], "empty query must preserve input order")
        XCTAssertEqual(result.map { $0.score }, [0, 0, 0], "empty query scores are 0")
        for sc in result {
            XCTAssertTrue(sc.matchedIndices.isEmpty, "empty query has no matched indices")
        }
        // No crash on empty candidate set either.
        XCTAssertEqual(FuzzyMatcher.match(query: "", in: []).count, 0)
        XCTAssertEqual(FuzzyMatcher.match(query: "x", in: []).count, 0)
    }

    // MARK: - 2. Exact full-string match scores strictly higher than a subsequence match.

    func testExactMatchBeatsSubsequence() {
        let exact = cand("cat")
        let subseq = cand("category")   // "cat" is a prefix/subsequence, not the whole string
        let result = FuzzyMatcher.match(query: "cat", in: [subseq, exact])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.candidate.title, "cat", "exact full-string match must rank first")

        let exactScore = try! XCTUnwrap(FuzzyMatcher.score(query: "cat", candidate: exact))
        let subseqScore = try! XCTUnwrap(FuzzyMatcher.score(query: "cat", candidate: subseq))
        XCTAssertGreaterThan(exactScore, subseqScore, "exact must score strictly higher than a longer subsequence host")
    }

    // MARK: - 3. Subsequence semantics: "abc" matches "axbxc" at [0,2,4]; does NOT match "acb".

    func testSubsequenceMatchingAndIndices() {
        let scored = try! XCTUnwrap(FuzzyMatcher.match(query: "abc", in: [cand("axbxc")]).first)
        XCTAssertEqual(scored.matchedIndices, [0, 2, 4], "subsequence indices must land on a,b,c")

        XCTAssertNotNil(FuzzyMatcher.score(query: "abc", candidate: cand("axbxc")))
        XCTAssertNil(FuzzyMatcher.score(query: "abc", candidate: cand("acb")),
                     "out-of-order chars are not a subsequence")
        XCTAssertEqual(FuzzyMatcher.match(query: "abc", in: [cand("acb")]).count, 0,
                       "non-match excluded from results")
    }

    // MARK: - 4. Word-boundary bonus: "gp" ranks "Git Push" above "Gimp".

    func testWordBoundaryBonus() {
        let result = FuzzyMatcher.match(query: "gp", in: [cand("Gimp"), cand("Git Push")])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.candidate.title, "Git Push",
                       "g+p both on word boundaries should outrank an in-word match")
        let gitPush = try! XCTUnwrap(FuzzyMatcher.score(query: "gp", candidate: cand("Git Push")))
        let gimp = try! XCTUnwrap(FuzzyMatcher.score(query: "gp", candidate: cand("Gimp")))
        XCTAssertGreaterThan(gitPush, gimp)
    }

    // MARK: - 5. Case-insensitivity.

    func testCaseInsensitivity() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "PR", candidate: cand("pull request")))
        XCTAssertNotNil(FuzzyMatcher.score(query: "pr", candidate: cand("Pull Request")))
        XCTAssertNotNil(FuzzyMatcher.score(query: "PR", candidate: cand("Pr…")))
        let result = FuzzyMatcher.match(query: "PR", in: [cand("pull request"), cand("nope")])
        XCTAssertEqual(titles(result), ["pull request"])
    }

    // MARK: - 6. Consecutive-run bonus: "stra" ranks "stranger" above gapped "s_t_r_a".

    func testConsecutiveRunBonus() {
        let result = FuzzyMatcher.match(query: "stra", in: [cand("s_t_r_a"), cand("stranger")])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.candidate.title, "stranger",
                       "a consecutive run should beat a gapped match")
        let consecutive = try! XCTUnwrap(FuzzyMatcher.score(query: "stra", candidate: cand("stranger")))
        let gapped = try! XCTUnwrap(FuzzyMatcher.score(query: "stra", candidate: cand("s_t_r_a")))
        XCTAssertGreaterThan(consecutive, gapped)
    }

    // MARK: - 7. Unicode: "café" matches "Café Menu"; combining marks don't crash.

    func testUnicodeMatching() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "café", candidate: cand("Café Menu")),
                        "precomposed query should match")
        // Decomposed (combining acute) form of the same word — must normalize & match.
        let decomposed = "Cafe\u{0301} Menu" // "Café Menu" with combining mark
        XCTAssertNotNil(FuzzyMatcher.score(query: "café", candidate: cand(decomposed)),
                        "NFC/NFD forms must compare equal after normalization")
        // Stray combining marks must not crash.
        XCTAssertNoThrow(FuzzyMatcher.match(query: "e\u{0301}", in: [cand("e\u{0301}\u{0301}\u{0301}")]))
        let result = FuzzyMatcher.match(query: "café", in: [cand("Café Menu"), cand("Tea House")])
        XCTAssertEqual(titles(result), ["Café Menu"])
    }

    // MARK: - 8. keywords participate.

    func testKeywordsParticipate() {
        let c = cand("Repository", keywords: ["repo", "vcs"])
        XCTAssertNotNil(FuzzyMatcher.score(query: "repo", candidate: c),
                        "a keyword should make the candidate match")
        let result = FuzzyMatcher.match(query: "repo", in: [c, cand("Unrelated")])
        XCTAssertEqual(titles(result), ["Repository"])

        // Best-over-the-set: a strong keyword hit should not score worse than a weak title hit.
        let titleOnly = cand("Répürtörü")          // "repo" only as a weak scattered subsequence
        let keywordHit = cand("Something", keywords: ["repo"])
        let tScore = FuzzyMatcher.score(query: "repo", candidate: titleOnly)
        let kScore = try! XCTUnwrap(FuzzyMatcher.score(query: "repo", candidate: keywordHit))
        if let tScore { XCTAssertGreaterThanOrEqual(kScore, tScore) }
    }

    // MARK: - 9. matchedIndices monotonic increasing & in bounds.

    func testMatchedIndicesValid() {
        let candidates = [
            cand("axbxc"),
            cand("Git Push"),
            cand("stranger"),
            cand("pull request"),
        ]
        for query in ["abc", "gp", "stra", "pr", "us"] {
            for sc in FuzzyMatcher.match(query: query, in: candidates) {
                let charCount = sc.candidate.title.precomposedStringWithCanonicalMapping.count
                let idx = sc.matchedIndices
                XCTAssertEqual(idx.count, query.count,
                               "one matched index per query char (title matches)")
                // strictly increasing
                for i in 1..<max(idx.count, 1) where idx.count > 1 {
                    XCTAssertLessThan(idx[i - 1], idx[i], "indices must be strictly increasing")
                }
                for i in idx {
                    XCTAssertGreaterThanOrEqual(i, 0)
                    XCTAssertLessThan(i, charCount, "index must be within the matched string")
                }
            }
        }
    }

    // MARK: - 10. Perf: 10k candidates, query "abc", ranked < 5ms (release) / generous (debug).

    func testPerformance10kCandidates() {
        // Synthesize 10,000 candidates. Mix matches and non-matches.
        var candidates: [Candidate] = []
        candidates.reserveCapacity(10_000)
        let fillers = ["alphabet soup", "xyzzy gadget", "the quick brown fox",
                       "abracadabra", "no match here", "back to basics", "cab driver"]
        for i in 0..<10_000 {
            let base = fillers[i % fillers.count]
            candidates.append(Candidate(id: "id-\(i)",
                                        title: "\(base) \(i)",
                                        keywords: ["kw\(i % 13)", "tag-abc-\(i % 7)"]))
        }

        // Architecture (docs §1.5): candidates are normalized + boundary-masked ONCE
        // at ingest (`prepare`), then filtered natively PER KEYSTROKE. The <5ms budget
        // governs the per-keystroke filter, not the one-time ingest. So precompute
        // here (as the host does on setCandidates) and time only the keystroke path.
        let prepared = FuzzyMatcher.prepare(candidates)

        // Warm up (buffer growth, branch-predictor / cache warmth).
        _ = FuzzyMatcher.match(query: "abc", inPrepared: prepared)

        let iterations = 5
        var best = Double.greatestFiniteMagnitude
        var lastCount = 0
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            let result = FuzzyMatcher.match(query: "abc", inPrepared: prepared)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            best = min(best, elapsedMs)
            lastCount = result.count
        }
        XCTAssertGreaterThan(lastCount, 0, "query 'abc' should match a good fraction of 10k candidates")

        // Sanity: the convenience `match(query:in:)` entrypoint (which re-ingests)
        // returns the same ranking as the prepared path.
        let viaConvenience = FuzzyMatcher.match(query: "abc", in: candidates)
        XCTAssertEqual(viaConvenience.count, lastCount,
                       "convenience and prepared paths must agree on match set")

        print("VeeFuzzy perf: 10k prepared candidates, query 'abc' best of \(iterations) = \(best) ms")

        #if DEBUG
        // Debug builds carry bounds-checking & no optimization and run ~40x slower
        // than release for this array-heavy DP (observed ~115 ms here vs ~2.4 ms
        // release). Keep the gate generous so it isn't flaky on a loaded machine,
        // but tight enough to catch a pathological O(n²) regression. The real
        // build-plan budget is the release number below.
        let budgetMs = 400.0
        #else
        // Release: the strict build-plan budget for per-keystroke filtering.
        let budgetMs = 5.0
        #endif
        XCTAssertLessThan(best, budgetMs,
                          "10k-candidate per-keystroke filter exceeded budget (\(budgetMs) ms): measured \(best) ms")
    }
}
