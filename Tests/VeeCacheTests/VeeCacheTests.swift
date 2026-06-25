import XCTest
@testable import VeeCache
import VeeProtocol

/// VeeCache TDD suite — build plan §4 (stale-while-revalidate, RFC 5861).
///
/// Determinism: every time-dependent test drives a `FakeClock` we advance by
/// hand (no wall-clock sleeps), and the revalidator is an injected async
/// closure the test controls — it can count invocations, gate completion on a
/// continuation, or throw on demand.
final class VeeCacheTests: XCTestCase {

    // MARK: Helpers

    /// A revalidator we can drive: counts calls, returns a scripted value, and
    /// can be made to throw. Thread-safe because concurrent stale reads may hit
    /// it from multiple tasks (the de-dup test asserts they do not).
    private final class Revalidator: @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        private var _next: String
        private var _shouldThrow = false

        /// Optional gate: when armed, `revalidate()` parks until `release()` is
        /// called, so a test can issue several concurrent reads *before* any
        /// revalidation is allowed to resolve — making in-flight de-dup
        /// deterministic instead of racing a synchronous revalidator.
        private var _gated = false
        private var _waiters: [CheckedContinuation<Void, Never>] = []

        init(next: String) { self._next = next }

        var callCount: Int { lock.withLock { _callCount } }

        func setNext(_ value: String) { lock.withLock { _next = value } }
        func setShouldThrow(_ flag: Bool) { lock.withLock { _shouldThrow = flag } }

        /// Arm the gate — subsequent `revalidate()` calls block until `release()`.
        func gate() { lock.withLock { _gated = true } }

        /// Open the gate and resume everyone parked on it.
        func release() {
            let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
                _gated = false
                let w = _waiters
                _waiters = []
                return w
            }
            for w in waiters { w.resume() }
        }

        /// The async closure handed to the cache. Uses scoped `withLock` (not
        /// `lock()`/`unlock()`, which are unavailable from async contexts).
        func revalidate() async throws -> String {
            let (value, willThrow, mustWait): (String, Bool, Bool) = lock.withLock {
                _callCount += 1
                return (_next, _shouldThrow, _gated)
            }
            if mustWait {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    lock.withLock { _waiters.append(cont) }
                }
            }
            if willThrow { throw CacheError.revalidationFailed }
            return value
        }
    }

    struct CacheError: Error, Equatable { let id: String; static let revalidationFailed = CacheError(id: "boom") }

    /// Collects errors surfaced by the cache's error sink.
    private final class ErrorSink: @unchecked Sendable {
        private let lock = NSLock()
        private var _errors: [Error] = []
        var count: Int { lock.withLock { _errors.count } }
        var last: Error? { lock.withLock { _errors.last } }
        func record(_ error: Error) { lock.withLock { _errors.append(error) } }
    }

    private func makeCache(
        clock: FakeClock,
        revalidator: Revalidator,
        sink: ErrorSink,
        minTimeToStale: TimeInterval = 10,
        maxTimeToLive: TimeInterval = 100,
        keepPreviousData: Bool = true,
        storage: InMemoryLRUStorage<CacheEntry<String>> = InMemoryLRUStorage(capacity: 16)
    ) -> SWRCache<String> {
        SWRCache(
            storage: storage,
            clock: clock,
            minTimeToStale: minTimeToStale,
            maxTimeToLive: maxTimeToLive,
            keepPreviousData: keepPreviousData,
            revalidate: { _ in try await revalidator.revalidate() },
            onError: { _, error in sink.record(error) }
        )
    }

    // MARK: 1. Miss — unknown key → nil, revalidator NOT called.

    func testMissReturnsNilWithoutRevalidating() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "v")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink)

        let value = await cache.get("absent")
        XCTAssertNil(value)
        XCTAssertEqual(rev.callCount, 0, "a pure miss must not trigger revalidation")
    }

    // MARK: 2. Fresh hit (< minTimeToStale) → cached value, NO revalidation.

    func testFreshHitReturnsCachedValueNoRevalidation() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "fresh-from-revalidator")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10)

        await cache.set("k", value: "cached")
        clock.advance(by: 5) // still < minTimeToStale (10)

        let value = await cache.get("k")
        XCTAssertEqual(value, "cached")
        XCTAssertEqual(rev.callCount, 0, "fresh data must not revalidate")
    }

    // MARK: 3. Stale hit → stale value immediately AND exactly ONE revalidation.

    func testStaleHitReturnsStaleAndFiresExactlyOneRevalidation() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "new")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "stale")
        clock.advance(by: 20) // > minTimeToStale, < maxTimeToLive

        let value = await cache.get("k")
        XCTAssertEqual(value, "stale", "stale read must return immediately with the old value")

        // Let the fired background revalidation settle.
        await cache.drainPendingRevalidations()
        XCTAssertEqual(rev.callCount, 1, "exactly one revalidation should have fired")
    }

    // MARK: 4. Revalidate swap — after revalidator resolves, next get is the new value.

    func testRevalidateSwapsInNewValue() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "v2")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "v1")
        clock.advance(by: 20)

        let stale = await cache.get("k")
        XCTAssertEqual(stale, "v1")
        await cache.drainPendingRevalidations()

        // The swapped value is now fresh (timestamp = clock.now), so this read
        // returns the new value without another revalidation.
        let fresh = await cache.get("k")
        XCTAssertEqual(fresh, "v2", "the revalidated value should be served on the next read")
        XCTAssertEqual(rev.callCount, 1)
    }

    // MARK: 5. TTL expiry (> maxTimeToLive) → treated as miss, await fresh.

    func testTTLExpiryTreatedAsMissAndAwaitsFresh() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "rebuilt")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "expired")
        clock.advance(by: 150) // > maxTimeToLive (100)

        let value = await cache.get("k")
        // A hard-expired entry is a miss: the caller blocks for fresh data.
        XCTAssertEqual(value, "rebuilt", "expired entry must await a fresh value, not serve stale")
        XCTAssertEqual(rev.callCount, 1)
    }

    // MARK: 6. In-flight de-dup — two concurrent stale reads → only ONE revalidation.

    func testConcurrentStaleReadsDeduplicateToOneRevalidation() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "deduped")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "stale")
        clock.advance(by: 20)

        // Gate the revalidator so it cannot resolve (and swap in fresh data)
        // until all concurrent reads have been issued — otherwise a synchronous
        // revalidator could win the race and a later read would see fresh data.
        rev.gate()

        // Fire many concurrent stale reads against the same key. Each must see
        // the old value immediately while sharing ONE in-flight revalidation.
        await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 { group.addTask { await cache.get("k") } }
            for await result in group {
                XCTAssertEqual(result, "stale", "every concurrent stale read sees the old value immediately")
            }
        }

        // All stale reads returned; now let the single revalidation finish.
        rev.release()
        await cache.drainPendingRevalidations()
        XCTAssertEqual(rev.callCount, 1, "concurrent stale reads must share a single in-flight revalidation")
    }

    // MARK: 7. LRU eviction — capacity N → N+1th insert evicts LRU.

    func testLRUEvictsLeastRecentlyUsed() async throws {
        let storage = InMemoryLRUStorage<CacheEntry<String>>(capacity: 2)

        storage.set("a", value: CacheEntry(value: "A", storedAt: Date()))
        storage.set("b", value: CacheEntry(value: "B", storedAt: Date()))
        // Touch "a" so "b" becomes the LRU.
        _ = storage.get("a")
        storage.set("c", value: CacheEntry(value: "C", storedAt: Date())) // evicts "b"

        XCTAssertNotNil(storage.get("a"), "recently used key survives")
        XCTAssertNil(storage.get("b"), "least-recently-used key was evicted")
        XCTAssertNotNil(storage.get("c"), "newest key present")
    }

    // MARK: 8. invalidate(key) → next get misses.

    func testInvalidateCausesMiss() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "v")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "value")
        await cache.invalidate("k")

        // After invalidation the entry is gone → a get must rebuild via the
        // revalidator (it is no longer a fresh/stale hit; it's a miss).
        let value = await cache.get("k")
        XCTAssertEqual(value, "v")
        XCTAssertEqual(rev.callCount, 1, "invalidated key is a miss, so it revalidates")
    }

    // MARK: 9. DiskStorage persistence — set, then a fresh instance round-trips.

    func testDiskStoragePersistsAcrossInstances() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let storedAt = Date(timeIntervalSince1970: 1_000)
        do {
            let disk = try DiskStorage<CacheEntry<String>>(directory: dir)
            disk.set("token", value: CacheEntry(value: "secret-payload", storedAt: storedAt))
        }

        // A brand-new instance pointed at the same directory must read it back.
        let reopened = try DiskStorage<CacheEntry<String>>(directory: dir)
        let entry = reopened.get("token")
        XCTAssertEqual(entry?.value, "secret-payload")
        XCTAssertEqual(entry?.storedAt, storedAt)

        reopened.invalidate("token")
        XCTAssertNil(reopened.get("token"), "invalidate removes the on-disk entry")
    }

    // MARK: 10. Throwing revalidator leaves stale intact AND surfaces to error sink.

    func testThrowingRevalidatorKeepsStaleAndSurfacesError() async throws {
        let clock = FakeClock()
        let rev = Revalidator(next: "never-applied")
        let sink = ErrorSink()
        let cache = makeCache(clock: clock, revalidator: rev, sink: sink, minTimeToStale: 10, maxTimeToLive: 100)

        await cache.set("k", value: "stable")
        clock.advance(by: 20)
        rev.setShouldThrow(true)

        let stale = await cache.get("k")
        XCTAssertEqual(stale, "stable", "stale value returned immediately even though revalidation will fail")

        await cache.drainPendingRevalidations()

        // The cached value is untouched (no corruption) ...
        clock.advance(by: 0)
        let stillStale = await cache.get("k")
        XCTAssertEqual(stillStale, "stable", "a failed revalidation must not corrupt or drop the cached value")
        // ... and the error reached the sink.
        XCTAssertGreaterThanOrEqual(sink.count, 1, "the revalidation error must surface to the error sink")
        XCTAssertTrue(sink.last is CacheError)
    }
}
