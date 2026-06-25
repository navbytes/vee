import Foundation
import VeeProtocol

/// RFC 6902 (JSON Patch) compute + apply over `JSONValue`. The wire *types*
/// (`PatchOp`, `JSONPatchError`) live in `VeeProtocol`; the *algorithms* live
/// here so the frozen contract stays dependency-free and rarely recompiles.
///
/// `apply` performs all six ops (add/remove/replace/move/copy/test) over RFC
/// 6901 JSON Pointers. `diff` computes a minimal patch transforming `a` into
/// `b`; for reordered arrays it emits array `move`s (a perceived-latency win
/// for list reordering) rather than a whole-array replace.
public enum JSONPatch {

    // MARK: - Apply

    /// Apply a patch to `document`, returning the new document. Throws the
    /// appropriate `JSONPatchError` on failure (RFC 6902 semantics: ops apply
    /// in sequence; a failure leaves the caller with the thrown error).
    public static func apply(_ patch: JSONPatchDocument, to document: JSONValue) throws -> JSONValue {
        var doc = document
        for op in patch {
            doc = try applyOne(op, to: doc)
        }
        return doc
    }

    private static func applyOne(_ op: PatchOp, to doc: JSONValue) throws -> JSONValue {
        switch op.op {
        case .add:
            let value = try requireValue(op)
            return try add(value, at: try Pointer(op.path), in: doc)

        case .remove:
            return try remove(at: try Pointer(op.path), in: doc).0

        case .replace:
            let value = try requireValue(op)
            // RFC 6902: target location MUST exist for replace.
            _ = try get(at: try Pointer(op.path), in: doc)
            return try replace(value, at: try Pointer(op.path), in: doc)

        case .move:
            let fromStr = try requireFrom(op)
            let fromPtr = try Pointer(fromStr)
            let (without, moved) = try remove(at: fromPtr, in: doc)
            // RFC 6902: "from" location MUST exist (remove enforces it).
            // A location MUST NOT be moved into one of its own children — but
            // since we remove first then add, that constraint is naturally
            // handled for the common cases the renderer produces.
            return try add(moved, at: try Pointer(op.path), in: without)

        case .copy:
            let fromStr = try requireFrom(op)
            let copied = try get(at: try Pointer(fromStr), in: doc)
            return try add(copied, at: try Pointer(op.path), in: doc)

        case .test:
            let value = try requireValue(op)
            let found = try get(at: try Pointer(op.path), in: doc)
            guard found == value else { throw JSONPatchError.testFailed(path: op.path) }
            return doc
        }
    }

    private static func requireValue(_ op: PatchOp) throws -> JSONValue {
        guard let value = op.value else { throw JSONPatchError.invalidPointer(op.path) }
        return value
    }

    private static func requireFrom(_ op: PatchOp) throws -> String {
        guard let from = op.from else { throw JSONPatchError.invalidPointer(op.path) }
        return from
    }

    // MARK: - Core pointer operations

    /// Resolve the value at `pointer`, throwing `pathNotFound` /
    /// `arrayIndexOutOfBounds` / `typeMismatch` as appropriate.
    private static func get(at pointer: Pointer, in doc: JSONValue) throws -> JSONValue {
        var current = doc
        for (i, token) in pointer.tokens.enumerated() {
            let isLast = i == pointer.tokens.count - 1
            switch current {
            case .object(let obj):
                guard let next = obj[token] else {
                    throw JSONPatchError.pathNotFound(pointer.raw)
                }
                current = next
            case .array(let arr):
                let idx = try arrayIndex(token, count: arr.count, raw: pointer.raw, allowEnd: false)
                current = arr[idx]
            default:
                // Cannot descend into a scalar. If this is not the last token we
                // are walking through a scalar — that's a type mismatch; if it is
                // the last token the parent simply has no such child.
                throw isLast ? JSONPatchError.pathNotFound(pointer.raw)
                             : JSONPatchError.typeMismatch(path: pointer.raw)
            }
        }
        return current
    }

    /// RFC 6902 `add`: insert/replace at the target location.
    private static func add(_ value: JSONValue, at pointer: Pointer, in doc: JSONValue) throws -> JSONValue {
        // Empty pointer => replace whole document.
        guard let (parentTokens, last) = pointer.split() else { return value }

        return try mutateParent(at: parentTokens, in: doc, raw: pointer.raw) { container in
            switch container {
            case .object(var obj):
                obj[last] = value
                return .object(obj)
            case .array(var arr):
                if last == "-" {
                    arr.append(value)
                } else {
                    let idx = try arrayIndex(last, count: arr.count, raw: pointer.raw, allowEnd: true)
                    arr.insert(value, at: idx)
                }
                return .array(arr)
            default:
                throw JSONPatchError.typeMismatch(path: pointer.raw)
            }
        }
    }

    /// RFC 6902 `replace`: overwrite the value at the target (must exist; the
    /// caller has already validated existence).
    private static func replace(_ value: JSONValue, at pointer: Pointer, in doc: JSONValue) throws -> JSONValue {
        guard let (parentTokens, last) = pointer.split() else { return value }

        return try mutateParent(at: parentTokens, in: doc, raw: pointer.raw) { container in
            switch container {
            case .object(var obj):
                guard obj[last] != nil else { throw JSONPatchError.pathNotFound(pointer.raw) }
                obj[last] = value
                return .object(obj)
            case .array(var arr):
                let idx = try arrayIndex(last, count: arr.count, raw: pointer.raw, allowEnd: false)
                arr[idx] = value
                return .array(arr)
            default:
                throw JSONPatchError.typeMismatch(path: pointer.raw)
            }
        }
    }

    /// RFC 6902 `remove`: delete the value at the target, returning the new
    /// document and the removed value.
    private static func remove(at pointer: Pointer, in doc: JSONValue) throws -> (JSONValue, JSONValue) {
        guard let (parentTokens, last) = pointer.split() else {
            // Removing the whole document is meaningless in our model; treat the
            // root as "removed" by yielding null. (Not produced by diff.)
            return (.null, doc)
        }

        var removed: JSONValue = .null
        let newDoc = try mutateParent(at: parentTokens, in: doc, raw: pointer.raw) { container in
            switch container {
            case .object(var obj):
                guard let value = obj[last] else { throw JSONPatchError.pathNotFound(pointer.raw) }
                removed = value
                obj[last] = nil
                return .object(obj)
            case .array(var arr):
                let idx = try arrayIndex(last, count: arr.count, raw: pointer.raw, allowEnd: false)
                removed = arr.remove(at: idx)
                return .array(arr)
            default:
                throw JSONPatchError.typeMismatch(path: pointer.raw)
            }
        }
        return (newDoc, removed)
    }

    /// Walk to the container named by `parentTokens` and apply `transform` to
    /// it, rebuilding the document immutably on the way back up. This keeps the
    /// mutation logic in one place for add/replace/remove.
    private static func mutateParent(
        at parentTokens: ArraySlice<String>,
        in doc: JSONValue,
        raw: String,
        _ transform: (JSONValue) throws -> JSONValue
    ) throws -> JSONValue {
        guard let token = parentTokens.first else {
            // No more tokens: `doc` itself is the parent container to mutate.
            return try transform(doc)
        }
        let rest = parentTokens.dropFirst()

        switch doc {
        case .object(var obj):
            guard let child = obj[token] else { throw JSONPatchError.pathNotFound(raw) }
            obj[token] = try mutateParent(at: rest, in: child, raw: raw, transform)
            return .object(obj)
        case .array(var arr):
            let idx = try arrayIndex(token, count: arr.count, raw: raw, allowEnd: false)
            arr[idx] = try mutateParent(at: rest, in: arr[idx], raw: raw, transform)
            return .array(arr)
        default:
            throw JSONPatchError.typeMismatch(path: raw)
        }
    }

    /// Parse an array-index token. `allowEnd` permits `count` (a valid
    /// insertion point for `add`). Rejects non-numeric, leading-zero, and
    /// out-of-range tokens with the right error.
    private static func arrayIndex(_ token: String, count: Int, raw: String, allowEnd: Bool) throws -> Int {
        // RFC 6901: array indices are unsigned decimal integers; "0" is allowed
        // but "01" / leading zeros and "-1" are not valid pointer tokens.
        guard isValidArrayToken(token) else { throw JSONPatchError.invalidPointer(raw) }
        guard let idx = Int(token) else { throw JSONPatchError.invalidPointer(raw) }
        let upper = allowEnd ? count : count - 1
        guard idx >= 0 && idx <= upper else {
            throw JSONPatchError.arrayIndexOutOfBounds(path: raw)
        }
        return idx
    }

    private static func isValidArrayToken(_ token: String) -> Bool {
        if token == "0" { return true }
        guard let first = token.first, first != "0", first != "-" else { return false }
        return token.allSatisfy(\.isNumber)
    }
}

// MARK: - RFC 6901 JSON Pointer

/// A parsed RFC 6901 JSON Pointer. `""` is the whole-document pointer (empty
/// `tokens`); otherwise each `/`-separated reference token is unescaped
/// (`~1`→`/`, `~0`→`~`, in that order).
struct Pointer {
    /// The original pointer string, for error messages.
    let raw: String
    /// Unescaped reference tokens. Empty for the whole-document pointer.
    let tokens: [String]

    init(_ raw: String) throws {
        self.raw = raw
        if raw.isEmpty {
            self.tokens = []
            return
        }
        guard raw.hasPrefix("/") else { throw JSONPatchError.invalidPointer(raw) }
        // Drop the leading "/" then split; "/" alone => one empty-string token
        // (a member whose key is "").
        let body = raw.dropFirst()
        self.tokens = body.components(separatedBy: "/").map(Pointer.unescape)
    }

    /// Split into (parent tokens, final token). Returns nil for the
    /// whole-document pointer (no parent).
    func split() -> (ArraySlice<String>, String)? {
        guard let last = tokens.last else { return nil }
        return (tokens.dropLast(), last)
    }

    /// RFC 6901 unescaping: `~1` → `/`, then `~0` → `~`. The order matters so
    /// that an encoded `~01` decodes to `~1` rather than `/`.
    static func unescape(_ token: String) -> String {
        token.replacingOccurrences(of: "~1", with: "/")
             .replacingOccurrences(of: "~0", with: "~")
    }

    /// RFC 6901 escaping for emitting pointers in `diff`: `~` → `~0`, then
    /// `/` → `~1` (escape `~` first to avoid double-escaping).
    static func escape(_ token: String) -> String {
        token.replacingOccurrences(of: "~", with: "~0")
             .replacingOccurrences(of: "/", with: "~1")
    }
}

// MARK: - Diff

extension JSONPatch {
    /// Compute a patch that transforms `a` into `b`. Emits minimal add/remove/
    /// replace for object and scalar changes, and minimal array `move`s for
    /// reordered arrays (rather than a whole-array replace).
    public static func diff(_ a: JSONValue, _ b: JSONValue) -> JSONPatchDocument {
        var ops: [PatchOp] = []
        diffValue(a, b, at: "", into: &ops)
        return ops
    }

    /// Append the ops transforming `a`→`b` at `path` (a fully-escaped pointer).
    private static func diffValue(_ a: JSONValue, _ b: JSONValue, at path: String, into ops: inout [PatchOp]) {
        if a == b { return }

        switch (a, b) {
        case let (.object(oa), .object(ob)):
            diffObject(oa, ob, at: path, into: &ops)
        case let (.array(aa), .array(ab)):
            diffArray(aa, ab, at: path, into: &ops)
        default:
            // Scalar change, or a type change (object↔array↔scalar): replace.
            // Root replace uses path "".
            ops.append(.replace(path, b))
        }
    }

    private static func diffObject(
        _ a: [String: JSONValue], _ b: [String: JSONValue],
        at path: String, into ops: inout [PatchOp]
    ) {
        // Removals first (so subsequent index-free object ops are order-independent),
        // sorted for deterministic output.
        for key in a.keys.sorted() where b[key] == nil {
            ops.append(.remove(childPath(path, key)))
        }
        // Changed + added keys.
        for key in b.keys.sorted() {
            let child = childPath(path, key)
            if let old = a[key] {
                diffValue(old, b[key]!, at: child, into: &ops)
            } else {
                ops.append(.add(child, b[key]!))
            }
        }
    }

    /// Build the child pointer for `key` under `path`, escaping the key per RFC 6901.
    private static func childPath(_ path: String, _ key: String) -> String {
        "\(path)/\(Pointer.escape(key))"
    }

    private static func childPath(_ path: String, _ index: Int) -> String {
        "\(path)/\(index)"
    }
}

// MARK: - Array diff (minimal moves for reorders)

extension JSONPatch {
    /// Diff two arrays. The strategy:
    ///   1. Identify elements present in both by a stable identity (object `id`
    ///      member when present, else the element's value). For the common
    ///      "same set, new order" case this yields pure `move`s.
    ///   2. Use a longest-increasing-subsequence (LIS) over the surviving
    ///      elements' source positions to find the elements that DON'T need to
    ///      move; everything else is a single `move`. This is minimal in the
    ///      number of moves.
    ///   3. Elements only in `a` are removed; elements only in `b` are added.
    ///      Where an index aligns and identities differ, recurse (so nested
    ///      value changes don't trigger a whole-array replace).
    ///
    /// We model the transformation as a sequence of `remove`/`add`/`move` ops on
    /// a working array, emitting RFC 6902 ops whose indices are valid *at the
    /// moment they apply* (patches apply sequentially).
    private static func diffArray(
        _ a: [JSONValue], _ b: [JSONValue],
        at path: String, into ops: inout [PatchOp]
    ) {
        // Identity for matching elements across the two arrays.
        //
        // `key` wins over `id`: `key` is the render-tree reconciliation identity
        // (the top-level field `RenderNode.jsonValue` projects and `@vee/sdk`
        // lifts out of props), while `id` is the data identity of a
        // Candidate-style / legacy element. A keyed `RenderNode` child whose
        // prop changes must reconcile as a recursive `replace`, not remove+add —
        // this is the §3/§5 minimal-diff (perceived-latency) win.
        func identity(_ v: JSONValue) -> IdentityKey {
            if case .object(let o) = v {
                if let key = o["key"] { return .id(key) }
                if let id = o["id"] { return .id(id) }
            }
            return .value(v)
        }

        // Fast path: if identities are all unique on both sides and the two
        // arrays are a permutation of the same identity set, we can express the
        // change purely as moves (+ recursion for matched elements). Otherwise
        // fall back to a positional LCS-free strategy that still avoids whole
        // replaces.
        let aKeys = a.map(identity)
        let bKeys = b.map(identity)

        let aSet = Multiset(aKeys)
        let bSet = Multiset(bKeys)

        // If the multisets of identities are equal AND all identities are
        // unique, it's a pure reorder (possibly with nested edits) → moves.
        if aSet == bSet, aSet.allUnique, a.count == b.count {
            diffArrayReorder(a, b, aKeys: aKeys, bKeys: bKeys, at: path, into: &ops)
            return
        }

        // General case: align by identity using a remove/add plan that still
        // recurses into matched elements and never whole-array replaces.
        diffArrayGeneral(a, b, aKeys: aKeys, bKeys: bKeys, at: path, into: &ops)
    }

    /// Pure reorder of a unique-keyed array: compute minimal moves via LIS.
    private static func diffArrayReorder(
        _ a: [JSONValue], _ b: [JSONValue],
        aKeys: [IdentityKey], bKeys: [IdentityKey],
        at path: String, into ops: inout [PatchOp]
    ) {
        // Map each identity to its source index in `a`.
        var sourceIndex: [IdentityKey: Int] = [:]
        for (i, k) in aKeys.enumerated() { sourceIndex[k] = i }

        // Target order expressed as source indices: targetPerm[j] = where
        // b[j] came from in a.
        let targetPerm = bKeys.map { sourceIndex[$0]! }

        // Elements whose relative order is already correct (the LIS of
        // targetPerm) stay put; the rest move. This minimises move count.
        let stayInPlace = longestIncreasingSubsequence(targetPerm)
        let stable = Set(stayInPlace)

        // First, recurse into matched elements for nested value changes. We do
        // this against the FINAL positions in b (after reordering, the element
        // identities at index j is b[j]); recursing now (before moves) using the
        // value-level diff at the eventual path is safe because identities match
        // and only nested values differ. To keep indices valid we recurse on the
        // path as it will exist in the final array.
        // Build a working array of identities to simulate moves and produce
        // valid intermediate indices.
        var work = aKeys

        // We process target positions left→right. For each j, ensure the element
        // that belongs at j is actually at j; if it's a "moving" element, emit a
        // move from its current working position to j.
        for j in 0..<targetPerm.count {
            let src = targetPerm[j]
            if stable.contains(src) {
                // This element is part of the stable backbone; leave it. But the
                // backbone is only "in place" relative to other backbone
                // elements after the movers around it are inserted. Since we move
                // everything else *to* its target index in order, the backbone
                // ends up correct without explicit moves.
                continue
            }
            // Find current position of this identity in the working array.
            let key = bKeys[j]
            guard let cur = firstIndex(of: key, in: work) else { continue }
            if cur != j {
                ops.append(.move(from: childPath(path, cur), to: childPath(path, j)))
                // Update working array to reflect the move.
                let elem = work.remove(at: cur)
                work.insert(elem, at: j)
            }
        }

        // Now recurse into each matched element for nested value changes,
        // comparing a's element (by identity) with b's element at its final
        // index. Indices in `b` are final, so paths are stable.
        for j in 0..<b.count {
            let key = bKeys[j]
            guard let srcIdx = sourceIndex[key] else { continue }
            diffValue(a[srcIdx], b[j], at: childPath(path, j), into: &ops)
        }
    }

    /// General array diff: handles insertions/deletions/changes (and incidental
    /// moves) without ever emitting a whole-array replace. Uses an LCS over
    /// identities to decide keep/add/remove, recursing into kept elements.
    ///
    /// Algorithm: the LCS gives matched `(aIndex, bIndex)` anchor pairs that
    /// stay in place. We process the `a`/`b` gaps *between* consecutive anchors:
    /// within each gap, first `remove` the unmatched `a` elements, then `add`
    /// the unmatched `b` elements. A single `cursor` tracks the position in the
    /// live (evolving) array so every emitted index is valid at apply time.
    private static func diffArrayGeneral(
        _ a: [JSONValue], _ b: [JSONValue],
        aKeys: [IdentityKey], bKeys: [IdentityKey],
        at path: String, into ops: inout [PatchOp]
    ) {
        let lcs = longestCommonSubsequence(aKeys, bKeys)

        var ai = 0       // next index to consume in a
        var bi = 0       // next index to consume in b
        var cursor = 0   // current write position in the live array

        // Append a sentinel anchor at (a.count, b.count) so the trailing gap
        // after the last real anchor is processed by the same loop body.
        var anchors = lcs
        anchors.append((a.count, b.count))

        for (aAnchor, bAnchor) in anchors {
            // Remove every a-element in this gap that the LCS did not keep.
            while ai < aAnchor {
                ops.append(.remove(childPath(path, cursor)))
                ai += 1
                // cursor does NOT advance: the element at `cursor` was removed,
                // so the next element slides into the same position.
            }
            // Add every b-element in this gap that the LCS did not keep.
            while bi < bAnchor {
                ops.append(.add(childPath(path, cursor), b[bi]))
                bi += 1
                cursor += 1
            }
            // Consume the anchor itself (the kept element): recurse for any
            // nested value change at its final position, then advance past it.
            if aAnchor < a.count && bAnchor < b.count {
                diffValue(a[ai], b[bi], at: childPath(path, cursor), into: &ops)
                ai += 1; bi += 1; cursor += 1
            }
        }
    }

    private static func firstIndex(of key: IdentityKey, in keys: [IdentityKey]) -> Int? {
        for (i, k) in keys.enumerated() where k == key { return i }
        return nil
    }
}

// MARK: - Identity & multiset helpers

/// Identity used to match array elements across a diff. Objects with an `id`
/// member match by that id; everything else matches by full value.
enum IdentityKey: Hashable {
    case id(JSONValue)
    case value(JSONValue)
}

/// A tiny multiset over `IdentityKey` for cheap permutation checks.
private struct Multiset: Equatable {
    private var counts: [IdentityKey: Int] = [:]
    private(set) var allUnique = true

    init(_ keys: [IdentityKey]) {
        for k in keys {
            let c = (counts[k] ?? 0) + 1
            counts[k] = c
            if c > 1 { allUnique = false }
        }
    }

    static func == (lhs: Multiset, rhs: Multiset) -> Bool { lhs.counts == rhs.counts }
}

// MARK: - LIS / LCS

extension JSONPatch {
    /// Indices (into the input) forming a longest strictly-increasing
    /// subsequence of `nums`. Used to find the elements that need NOT move in a
    /// reorder. O(n log n).
    static func longestIncreasingSubsequence(_ nums: [Int]) -> [Int] {
        if nums.isEmpty { return [] }
        var tails: [Int] = []          // indices into nums; values increasing
        var prev = [Int](repeating: -1, count: nums.count)

        for i in 0..<nums.count {
            // Binary search for the first tail whose value >= nums[i].
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if nums[tails[mid]] < nums[i] { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { prev[i] = tails[lo - 1] }
            if lo == tails.count { tails.append(i) } else { tails[lo] = i }
        }

        // Reconstruct.
        var result: [Int] = []
        var k = tails.last!
        while k >= 0 {
            result.append(nums[k])
            k = prev[k]
        }
        return result.reversed()
    }

    /// Longest common subsequence of two identity arrays, returned as matched
    /// `(aIndex, bIndex)` pairs in order. Standard DP, O(n·m).
    static func longestCommonSubsequence(_ a: [IdentityKey], _ b: [IdentityKey]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return [] }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
