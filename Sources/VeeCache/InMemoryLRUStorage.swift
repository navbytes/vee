import Foundation

/// A capacity-bounded in-memory store that evicts the least-recently-used key
/// once it is full. Both `get` and `set` count as "use", refreshing recency.
///
/// Backed by a dictionary for O(1) lookup plus a doubly-linked recency list so
/// eviction and touch are O(1). A single `NSLock` makes it `Sendable` and safe
/// for the concurrent access ``SWRCache`` performs.
public final class InMemoryLRUStorage<Value>: CacheStrategy, @unchecked Sendable
    where Value: Sendable {

    private final class Node {
        let key: String
        var value: Value
        var prev: Node?
        var next: Node?
        init(key: String, value: Value) { self.key = key; self.value = value }
    }

    private let lock = NSLock()
    private let capacity: Int
    private var map: [String: Node] = [:]
    // `head` = most-recently-used, `tail` = least-recently-used.
    private var head: Node?
    private var tail: Node?

    /// - Parameter capacity: maximum live entries; must be >= 1.
    public init(capacity: Int) {
        precondition(capacity >= 1, "InMemoryLRUStorage capacity must be >= 1")
        self.capacity = capacity
    }

    public func get(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard let node = map[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    public func set(_ key: String, value: Value) {
        lock.lock(); defer { lock.unlock() }
        if let node = map[key] {
            node.value = value
            moveToHead(node)
            return
        }
        let node = Node(key: key, value: value)
        map[key] = node
        addToHead(node)
        if map.count > capacity { evictTail() }
    }

    public func invalidate(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        guard let node = map.removeValue(forKey: key) else { return }
        unlink(node)
    }

    // MARK: Recency list (must be called with `lock` held)

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func unlink(_ node: Node) {
        let p = node.prev, n = node.next
        p?.next = n
        n?.prev = p
        if head === node { head = n }
        if tail === node { tail = p }
        node.prev = nil; node.next = nil
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        unlink(node)
        addToHead(node)
    }

    private func evictTail() {
        guard let lru = tail else { return }
        unlink(lru)
        map.removeValue(forKey: lru.key)
    }
}
