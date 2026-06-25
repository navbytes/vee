import Foundation
import VeeProtocol

/// Stale-while-revalidate cache (RFC 5861 semantics), the core engine behind
/// Vee's `useCachedPromise`-style data flow (see `docs/ARCHITECTURE.md` §1.6).
///
/// On `get`:
///   * **Miss** (no entry, or hard-expired past `maxTimeToLive`) → `await` the
///     revalidator and return its fresh value (a hard-expired entry is treated
///     as a miss, not served stale).
///   * **Fresh** (age `< minTimeToStale`) → return the cached value, no work.
///   * **Stale** (`minTimeToStale <= age < maxTimeToLive`) → return the cached
///     value *immediately* and fire **exactly one** background revalidation
///     that atomically swaps the entry on success.
///
/// In-flight de-duplication: concurrent reads that would each trigger a
/// revalidation for the same key share one task (keyed by `key`). With
/// `keepPreviousData`, a stale read never blanks — the previous value is held
/// until fresh data lands, avoiding flicker.
///
/// The revalidator is an injected async closure (the host wires it to
/// `URLSession`/disk; tests control it to count calls and gate completion).
/// Errors from a background revalidation never corrupt the cached value; they
/// are routed to `onError`.
///
/// Modeled as an `actor` so the in-flight bookkeeping is race-free without
/// hand-rolled locking.
public actor SWRCache<Value: Sendable> {

    public typealias Revalidate = @Sendable (_ key: String) async throws -> Value
    public typealias ErrorSink = @Sendable (_ key: String, _ error: Error) -> Void

    /// Type-erased view of any ``CacheStrategy`` whose value is `CacheEntry<Value>`.
    /// Lets `SWRCache` accept arbitrary pluggable storage without a generic
    /// storage parameter leaking into every call site.
    private struct AnyStorage: Sendable {
        let get: @Sendable (String) -> CacheEntry<Value>?
        let set: @Sendable (String, CacheEntry<Value>) -> Void
        let invalidate: @Sendable (String) -> Void
    }

    private let storage: AnyStorage
    private let clock: any Clock
    private let minTimeToStale: TimeInterval
    private let maxTimeToLive: TimeInterval
    private let keepPreviousData: Bool
    private let revalidate: Revalidate
    private let onError: ErrorSink?

    /// One entry per key with a revalidation currently running — the heart of
    /// in-flight de-duplication.
    private var inFlight: [String: Task<Value, Error>] = [:]

    /// Keys the cache has "seen" (via `set` or a successful revalidation). A
    /// `get` for a never-seen key is a pure miss → `nil`, *without* invoking the
    /// revalidator: the caller has expressed no intent to populate it. Once a
    /// key is known, an expired or invalidated entry rebuilds via the
    /// revalidator. `invalidate` drops the value but keeps the key known so the
    /// next `get` refetches.
    private var knownKeys: Set<String> = []

    public init<S: CacheStrategy>(
        storage: S,
        clock: any Clock = SystemClock(),
        minTimeToStale: TimeInterval,
        maxTimeToLive: TimeInterval,
        keepPreviousData: Bool = true,
        revalidate: @escaping Revalidate,
        onError: ErrorSink? = nil
    ) where S.Value == CacheEntry<Value> {
        self.storage = AnyStorage(
            get: { storage.get($0) },
            set: { storage.set($0, value: $1) },
            invalidate: { storage.invalidate($0) }
        )
        self.clock = clock
        self.minTimeToStale = minTimeToStale
        self.maxTimeToLive = maxTimeToLive
        self.keepPreviousData = keepPreviousData
        self.revalidate = revalidate
        self.onError = onError
    }

    // MARK: Public API

    /// Read a value, applying SWR policy. Returns `nil` only when there is no
    /// cached entry *and* the revalidator itself fails to produce one.
    public func get(_ key: String) async -> Value? {
        let entry = storage.get(key)

        if let entry {
            let age = clock.now.timeIntervalSince(entry.storedAt)

            if age < minTimeToStale {
                // Fresh — serve cached, no revalidation.
                return entry.value
            }

            if age < maxTimeToLive {
                // Stale — serve cached immediately, fire a single background
                // revalidation (de-duped per key). keepPreviousData means we
                // hold `entry.value` regardless of how that resolves.
                startRevalidation(key)
                return entry.value
            }
            // Hard-expired (age >= maxTimeToLive): fall through; treat as miss.
        }

        // Pure miss: a key we have never seen has no revalidator intent. Return
        // nil without fetching (build plan §4 case 1).
        guard knownKeys.contains(key) else { return nil }

        // Known-but-absent/expired — await fresh data. Concurrent missers for
        // the same key share one in-flight task.
        // On a miss whose revalidation failed there is nothing to serve. The
        // error was already routed to `onError` inside the revalidation task
        // (reported exactly once, whether the trigger was a stale read or a
        // miss), so we just surface nil here.
        return try? await awaitRevalidation(key)
    }

    /// Insert / overwrite a value, timestamped at the current clock instant.
    public func set(_ key: String, value: Value) {
        knownKeys.insert(key)
        storage.set(key, CacheEntry(value: value, storedAt: clock.now))
    }

    /// Drop a key's value. The next `get` is a miss that revalidates (the key
    /// stays "known").
    public func invalidate(_ key: String) {
        inFlight[key]?.cancel()
        inFlight[key] = nil
        storage.invalidate(key)
    }

    /// Forget a key entirely — drop its value *and* its known status, so the
    /// next `get` is a pure miss returning `nil` without revalidating.
    public func forget(_ key: String) {
        inFlight[key]?.cancel()
        inFlight[key] = nil
        knownKeys.remove(key)
        storage.invalidate(key)
    }

    /// Test/diagnostic hook: await every revalidation currently in flight so a
    /// caller can assert post-revalidation state deterministically.
    public func drainPendingRevalidations() async {
        // Snapshot, because tasks remove themselves on completion.
        let tasks = Array(inFlight.values)
        for task in tasks {
            _ = try? await task.value
        }
    }

    // MARK: In-flight de-duplication

    /// Fire-and-forget a background revalidation (used by the stale path). The
    /// caller has already returned the stale value.
    private func startRevalidation(_ key: String) {
        _ = revalidationTask(key)
    }

    /// Await the (possibly shared) revalidation for `key` (used by the miss
    /// path, which has nothing to serve until fresh data arrives).
    private func awaitRevalidation(_ key: String) async throws -> Value {
        try await revalidationTask(key).value
    }

    /// Return the in-flight task for `key`, creating one if none exists. This is
    /// the single choke point that guarantees concurrent triggers coalesce.
    private func revalidationTask(_ key: String) -> Task<Value, Error> {
        if let existing = inFlight[key] {
            return existing
        }
        let task = Task { [revalidate, weakSelf = self] () throws -> Value in
            do {
                let fresh = try await revalidate(key)
                // Swap atomically on success (leaves any existing stale value
                // untouched until this point, so a slow revalidation never
                // blanks the cache — keepPreviousData).
                await weakSelf.completeRevalidation(key, with: fresh)
                return fresh
            } catch {
                // A failed revalidation must NOT corrupt or drop the cached
                // value; we only route the error to the sink. This fires for
                // both stale-path (background) and miss-path failures, exactly
                // once per revalidation.
                await weakSelf.report(key, error)
                throw error
            }
        }
        inFlight[key] = task
        // Ensure the slot is cleared whether the revalidation succeeds or fails.
        Task { [weakSelf = self] in
            _ = try? await task.value
            await weakSelf.clearInFlight(key, expected: task)
        }
        return task
    }

    /// Route a revalidation error to the caller's sink.
    private func report(_ key: String, _ error: Error) {
        onError?(key, error)
    }

    /// Apply a freshly revalidated value (atomic swap). The in-flight slot is
    /// cleared by the trailing cleanup task once the revalidation settles.
    private func completeRevalidation(_ key: String, with value: Value) {
        knownKeys.insert(key)
        storage.set(key, CacheEntry(value: value, storedAt: clock.now))
    }

    /// Remove the in-flight entry for `key` iff it is still the task we expect
    /// (a later revalidation may already have replaced it).
    private func clearInFlight(_ key: String, expected: Task<Value, Error>) {
        if inFlight[key] == expected {
            inFlight[key] = nil
        }
    }
}
