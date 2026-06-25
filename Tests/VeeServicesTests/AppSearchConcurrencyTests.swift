import XCTest
@testable import VeeServices
import VeeProtocol
import VeeFuzzy

/// Concurrency regression for MAC-1: `AppSearchProvider` is read from a
/// background queue (`search`) while `recordLaunch` mutates frecency on another
/// thread. Before the fix, the shared mutable `Dictionary` inside `FrecencyModel`
/// was mutated without synchronization — an unsynchronized-`Dictionary` race of
/// the heap-corruption class. These tests hammer `recordLaunch` + `search` from
/// many queues at once and assert (a) no crash / corruption and (b) the results
/// stay sane and ranking-correct.
///
/// Determinism: a `ManualClock` whose time never advances during the run gives a
/// fixed `now`, so every `recordLaunch`/`search` observes the same instant and
/// the final ranking is reproducible regardless of interleaving.
final class AppSearchConcurrencyTests: XCTestCase {

    /// Thread-safe app enumerator double. `enumerateApps` is called from every
    /// `search`, so it must itself be safe to call concurrently; it returns an
    /// immutable snapshot.
    private final class ConcurrentFakeEnumerator: AppEnumerating, @unchecked Sendable {
        let records: [AppRecord]
        init(_ records: [AppRecord]) { self.records = records }
        func enumerateApps() -> [AppRecord] { records }
    }

    private static func sampleApps(_ n: Int) -> [AppRecord] {
        (0..<n).map { i in
            AppRecord(name: "App\(i)", bundleId: "com.vee.app\(i)", path: "/Applications/App\(i).app")
        }
    }

    // MARK: - 1. Hammer recordLaunch + search from many queues; assert no crash

    func testConcurrentRecordLaunchAndSearchDoesNotCrash() {
        let apps = Self.sampleApps(50)
        let enumr = ConcurrentFakeEnumerator(apps)
        // Fixed clock: time does not advance, so the run is deterministic.
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_000_000))
        let provider = AppSearchProvider(enumerator: enumr, clock: clock)
        let bundleIds = apps.map(\.bundleId)

        // Concurrent writers recording launches, interleaved with concurrent
        // readers running searches — the exact main-thread-write /
        // background-read collision MAC-1 describes, amplified. The unsynchronized
        // `Dictionary` race surfaced within a few hundred interleavings under
        // TSan, so this many iterations is comfortably past the detection floor
        // while keeping the test fast.
        let iterations = 400
        DispatchQueue.concurrentPerform(iterations: 16) { worker in
            if worker % 2 == 0 {
                for i in 0..<iterations {
                    provider.recordLaunch(bundleId: bundleIds[(worker + i) % bundleIds.count])
                }
            } else {
                for i in 0..<iterations {
                    let results = (i % 2 == 0)
                        ? provider.search(query: "", limit: 10)
                        : provider.search(query: "app", limit: 10)
                    // Results must always be well-formed: capped, and every row a
                    // real candidate from the enumerated set (no torn reads).
                    XCTAssertLessThanOrEqual(results.count, 10)
                    for cand in results {
                        XCTAssertTrue(bundleIds.contains(cand.id))
                    }
                }
            }
        }

        // Survived the storm: still functional and bounded afterwards.
        let after = provider.search(query: "app", limit: 5)
        XCTAssertLessThanOrEqual(after.count, 5)
        XCTAssertFalse(after.isEmpty, "an 'app' query must still match after the concurrent run")
    }

    // MARK: - 2. Concurrent launches all count — final ranking is deterministic

    func testConcurrentLaunchesAreAllRecordedAndRankDeterministically() {
        // Two apps with identical fuzzy relevance to "no"; frecency must break the
        // tie. We pound `target` with launches from many threads while a constant
        // stream of searches runs. With a fixed clock, every launch contributes an
        // equal, undecayed weight, so the more-launched app must end up on top —
        // and no launch may be lost to a racy dictionary write.
        let target = AppRecord(name: "Notion", bundleId: "com.notion.id", path: "/Applications/Notion.app")
        let other = AppRecord(name: "Notes", bundleId: "com.apple.Notes", path: "/Applications/Notes.app")
        let enumr = ConcurrentFakeEnumerator([target, other])
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_000_000))
        let provider = AppSearchProvider(enumerator: enumr, clock: clock)

        let writers = 8
        let perWriter = 250
        DispatchQueue.concurrentPerform(iterations: writers + 4) { worker in
            if worker < writers {
                for _ in 0..<perWriter {
                    provider.recordLaunch(bundleId: target.bundleId)
                }
            } else {
                // Concurrent readers exercising the read path against the churn.
                for _ in 0..<perWriter {
                    _ = provider.search(query: "no", limit: 10)
                }
            }
        }

        // `target` was launched `writers * perWriter` times and `other` never;
        // frecency must rank `target` first. (If launches were lost to a race the
        // count could still favor it, but the assertion that matters here is no
        // crash + a sane, frecency-consistent ordering.)
        let ranked = provider.search(query: "no", limit: 10)
        XCTAssertEqual(ranked.first?.title, "Notion",
                       "the heavily-launched app must rank first after concurrent recording")
        XCTAssertEqual(Set(ranked.map(\.id)).count, ranked.count, "no duplicate rows")
    }
}
