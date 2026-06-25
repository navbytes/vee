import Foundation
import VeeProtocol

/// A stored value plus the instant it was written. ``SWRCache`` wraps every
/// payload in one of these so staleness / TTL can be computed against an
/// injected ``Clock`` rather than reading wall-clock time at access.
public struct CacheEntry<Value>: Sendable where Value: Sendable {
    public var value: Value
    public var storedAt: Date

    public init(value: Value, storedAt: Date) {
        self.value = value
        self.storedAt = storedAt
    }
}

extension CacheEntry: Equatable where Value: Equatable {}
extension CacheEntry: Codable where Value: Codable {}

/// The pluggable storage interface a plugin author can implement to back the
/// SWR engine. Vee ships ``InMemoryLRUStorage`` and ``DiskStorage``; a plugin
/// may supply any conforming object (e.g. SQLite-, Keychain-, or
/// network-backed).
///
/// Implementations are plain key/value stores — they do **not** know about
/// staleness or TTL. ``SWRCache`` layers the stale-while-revalidate policy on
/// top, storing ``CacheEntry`` values so it can timestamp each write.
///
/// Conformers must be `Sendable` and safe for concurrent access: ``SWRCache``
/// reads and writes them from multiple tasks.
public protocol CacheStrategy: Sendable {
    associatedtype Value: Sendable
    func get(_ key: String) -> Value?
    func set(_ key: String, value: Value)
    func invalidate(_ key: String)
}
