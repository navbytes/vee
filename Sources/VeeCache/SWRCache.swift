import Foundation
import VeeProtocol

/// Pluggable cache storage. Plugin authors can supply their own object
/// implementing this; Vee ships an in-memory LRU and a disk-backed default.
///
/// > Wave 1b worker: implement `SWRCache` (stale read → background revalidate →
/// > atomic swap, in-flight de-dup, keepPreviousData semantics), `InMemoryLRUStorage`,
/// > `DiskStorage`, and an injectable `Clock` for deterministic TTL per build
/// > plan §4. Tests first.
public protocol CacheStrategy {
    associatedtype Value
    func get(_ key: String) -> Value?
    func set(_ key: String, value: Value, ttl: TimeInterval?)
    func invalidate(_ key: String)
}

/// Stale-while-revalidate cache (RFC 5861 semantics).
public final class SWRCache<Value> {
    public init() {}
    // Wave 0 stub: real implementation lands in Wave 1b.
}
