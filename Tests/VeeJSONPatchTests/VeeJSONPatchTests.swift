import XCTest
@testable import VeeJSONPatch
import VeeProtocol

/// RFC 6902 (JSON Patch) compute + apply test suite for VeeJSONPatch.
///
/// Build plan §4 — 10 cases, including the headline 1000-case property test
/// `apply(diff(a,b), a) == b` with a seeded RNG for reproducibility.
final class VeeJSONPatchTests: XCTestCase {

    // MARK: - 1. add to object inserts a key

    func testAddToObjectInsertsKey() throws {
        let doc: JSONValue = ["a": 1]
        let result = try JSONPatch.apply([.add("/b", 2)], to: doc)
        XCTAssertEqual(result, ["a": 1, "b": 2])
    }

    func testAddToObjectReplacesExistingKey() throws {
        // RFC 6902: add to an existing object member replaces its value.
        let doc: JSONValue = ["a": 1]
        let result = try JSONPatch.apply([.add("/a", 9)], to: doc)
        XCTAssertEqual(result, ["a": 9])
    }

    func testAddToWholeDocument() throws {
        // path "" replaces the whole document with value.
        let doc: JSONValue = ["a": 1]
        let result = try JSONPatch.apply([.add("", ["x": 5])], to: doc)
        XCTAssertEqual(result, ["x": 5])
    }

    // MARK: - 2. add to array index + append + out-of-range throws

    func testAddToArrayIndexInserts() throws {
        let doc: JSONValue = ["arr": [1, 2, 3]]
        // Insert at index 1: shifts the rest right.
        let result = try JSONPatch.apply([.add("/arr/1", 9)], to: doc)
        XCTAssertEqual(result, ["arr": [1, 9, 2, 3]])
    }

    func testAddToArrayAtZero() throws {
        let doc: JSONValue = ["arr": [1, 2]]
        let result = try JSONPatch.apply([.add("/arr/0", 0)], to: doc)
        XCTAssertEqual(result, ["arr": [0, 1, 2]])
    }

    func testAddToArrayAtCountInsertsAtEnd() throws {
        // index == count is a valid insertion point (append) per RFC 6902.
        let doc: JSONValue = ["arr": [1, 2]]
        let result = try JSONPatch.apply([.add("/arr/2", 3)], to: doc)
        XCTAssertEqual(result, ["arr": [1, 2, 3]])
    }

    func testAddToArrayDashAppends() throws {
        let doc: JSONValue = ["arr": [1, 2]]
        let result = try JSONPatch.apply([.add("/arr/-", 3)], to: doc)
        XCTAssertEqual(result, ["arr": [1, 2, 3]])
    }

    func testAddToArrayDashAppendsToEmpty() throws {
        let doc: JSONValue = ["arr": []]
        let result = try JSONPatch.apply([.add("/arr/-", "first")], to: doc)
        XCTAssertEqual(result, ["arr": ["first"]])
    }

    func testAddToArrayOutOfRangeThrows() throws {
        let doc: JSONValue = ["arr": [1, 2]]
        XCTAssertThrowsError(try JSONPatch.apply([.add("/arr/5", 9)], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .arrayIndexOutOfBounds(path: "/arr/5"))
        }
    }

    func testAddToArrayNegativeIndexThrows() throws {
        let doc: JSONValue = ["arr": [1, 2]]
        // Non-"-" non-numeric / negative array tokens are invalid pointers.
        XCTAssertThrowsError(try JSONPatch.apply([.add("/arr/-1", 9)], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .invalidPointer("/arr/-1"))
        }
    }

    // MARK: - 3. remove nested key removes only that key

    func testRemoveNestedKey() throws {
        let doc: JSONValue = ["outer": ["a": 1, "b": 2], "keep": true]
        let result = try JSONPatch.apply([.remove("/outer/a")], to: doc)
        XCTAssertEqual(result, ["outer": ["b": 2], "keep": true])
    }

    func testRemoveArrayElementShifts() throws {
        let doc: JSONValue = ["arr": [10, 20, 30]]
        let result = try JSONPatch.apply([.remove("/arr/1")], to: doc)
        XCTAssertEqual(result, ["arr": [10, 30]])
    }

    func testRemoveMissingKeyThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.remove("/nope")], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .pathNotFound("/nope"))
        }
    }

    func testRemoveArrayOutOfBoundsThrows() throws {
        let doc: JSONValue = ["arr": [1]]
        XCTAssertThrowsError(try JSONPatch.apply([.remove("/arr/3")], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .arrayIndexOutOfBounds(path: "/arr/3"))
        }
    }

    // MARK: - 4. replace root ("") swaps whole document

    func testReplaceRootSwapsWholeDocument() throws {
        let doc: JSONValue = ["a": 1, "b": [1, 2, 3]]
        let result = try JSONPatch.apply([.replace("", "totally new")], to: doc)
        XCTAssertEqual(result, "totally new")
    }

    func testReplaceNestedValue() throws {
        let doc: JSONValue = ["a": ["b": 1]]
        let result = try JSONPatch.apply([.replace("/a/b", 99)], to: doc)
        XCTAssertEqual(result, ["a": ["b": 99]])
    }

    func testReplaceMissingTargetThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.replace("/missing", 1)], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .pathNotFound("/missing"))
        }
    }

    // MARK: - 5. move (source gone) + copy (source present)

    func testMoveRemovesSource() throws {
        let doc: JSONValue = ["a": 1, "b": ["c": 2]]
        let result = try JSONPatch.apply([.move(from: "/a", to: "/b/c")], to: doc)
        XCTAssertEqual(result, ["b": ["c": 1]])
    }

    func testMoveWithinArray() throws {
        let doc: JSONValue = ["arr": [1, 2, 3]]
        // Move element at index 0 to index 2.
        let result = try JSONPatch.apply([.move(from: "/arr/0", to: "/arr/2")], to: doc)
        XCTAssertEqual(result, ["arr": [2, 3, 1]])
    }

    func testCopyKeepsSource() throws {
        let doc: JSONValue = ["a": 1, "b": 2]
        let result = try JSONPatch.apply([.copy(from: "/a", to: "/c")], to: doc)
        XCTAssertEqual(result, ["a": 1, "b": 2, "c": 1])
    }

    func testMoveMissingSourceThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.move(from: "/x", to: "/y")], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .pathNotFound("/x"))
        }
    }

    func testCopyMissingSourceThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.copy(from: "/x", to: "/y")], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .pathNotFound("/x"))
        }
    }

    // MARK: - 6. test: match = no-op; mismatch throws testFailed

    func testTestMatchingValueIsNoOp() throws {
        let doc: JSONValue = ["a": ["b": 42]]
        let result = try JSONPatch.apply([.test("/a/b", 42)], to: doc)
        XCTAssertEqual(result, doc)
    }

    func testTestRootMatches() throws {
        let doc: JSONValue = [1, 2, 3]
        let result = try JSONPatch.apply([.test("", [1, 2, 3])], to: doc)
        XCTAssertEqual(result, doc)
    }

    func testTestMismatchThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.test("/a", 2)], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .testFailed(path: "/a"))
        }
    }

    func testTestMissingPathThrows() throws {
        let doc: JSONValue = ["a": 1]
        XCTAssertThrowsError(try JSONPatch.apply([.test("/missing", 1)], to: doc)) { error in
            XCTAssertEqual(error as? JSONPatchError, .pathNotFound("/missing"))
        }
    }

    // MARK: - 7. No-op diff: diff(x, x) == []

    func testDiffIdenticalScalarsIsEmpty() {
        XCTAssertEqual(JSONPatch.diff(42, 42), [])
        XCTAssertEqual(JSONPatch.diff("s", "s"), [])
        XCTAssertEqual(JSONPatch.diff(true, true), [])
        XCTAssertEqual(JSONPatch.diff(.null, .null), [])
    }

    func testDiffIdenticalCompositesIsEmpty() {
        let v: JSONValue = ["a": [1, 2, ["x": "y"]], "b": ["c": [true, nil]]]
        XCTAssertEqual(JSONPatch.diff(v, v), [])
    }

    // MARK: - 8. Property test (headline): apply(diff(a,b), a) == b, 1000 cases

    func testPropertyApplyDiffRoundTrip() throws {
        var rng = SeededRNG(seed: 0x5EED_F00D_CAFE_1234)
        let cases = 1000
        for i in 0..<cases {
            let a = JSONValueGenerator.random(using: &rng, maxDepth: 4)
            let b = JSONValueGenerator.random(using: &rng, maxDepth: 4)
            let patch = JSONPatch.diff(a, b)
            do {
                let result = try JSONPatch.apply(patch, to: a)
                XCTAssertEqual(
                    result, b,
                    "Round-trip failed on case \(i).\n  a=\(a)\n  b=\(b)\n  patch=\(patch)\n  got=\(result)")
                if result != b { return }  // stop on first failure for a readable log
            } catch {
                XCTFail("apply threw on case \(i): \(error)\n  a=\(a)\n  b=\(b)\n  patch=\(patch)")
                return
            }
        }
    }

    func testPropertyApplyDiffIdentityRoundTrip() throws {
        // Also exercise a==b and shared-structure cases (diff against self / mutation).
        var rng = SeededRNG(seed: 0xABCD_1234_5678_9F0F)
        for i in 0..<200 {
            let a = JSONValueGenerator.random(using: &rng, maxDepth: 4)
            let patch = JSONPatch.diff(a, a)
            XCTAssertEqual(patch, [], "diff(a,a) must be empty on case \(i): a=\(a)")
            let result = try JSONPatch.apply(patch, to: a)
            XCTAssertEqual(result, a)
        }
    }

    // MARK: - 9. RFC 6901 pointer edge cases (~0, ~1, empty key)

    func testPointerEscapedSlash() throws {
        // Key "a/b" is referenced as "/a~1b".
        let doc: JSONValue = ["a/b": 1]
        let result = try JSONPatch.apply([.replace("/a~1b", 2)], to: doc)
        XCTAssertEqual(result, ["a/b": 2])
    }

    func testPointerEscapedTilde() throws {
        // Key "m~n" is referenced as "/m~0n".
        let doc: JSONValue = ["m~n": 1]
        let result = try JSONPatch.apply([.replace("/m~0n", 2)], to: doc)
        XCTAssertEqual(result, ["m~n": 2])
    }

    func testPointerTildeOneZeroOrdering() throws {
        // RFC 6901: ~1 -> "/" and ~0 -> "~". "/~01" decodes to key "~1".
        let doc: JSONValue = ["~1": "v"]
        let result = try JSONPatch.apply([.test("/~01", "v")], to: doc)
        XCTAssertEqual(result, doc)
    }

    func testPointerEmptyStringKey() throws {
        // RFC 6901: "/" references the member whose key is the empty string.
        let doc: JSONValue = ["": 5]
        let result = try JSONPatch.apply([.replace("/", 6)], to: doc)
        XCTAssertEqual(result, ["": 6])
    }

    func testPointerAddWithEscapedKey() throws {
        let doc: JSONValue = ["x": 1]
        let result = try JSONPatch.apply([.add("/a~1b", true)], to: doc)
        XCTAssertEqual(result, ["x": 1, "a/b": true])
    }

    func testDiffPreservesEscapedKeys() throws {
        // diff must emit pointers that round-trip keys containing / and ~.
        let a: JSONValue = ["a/b": 1, "c~d": 2]
        let b: JSONValue = ["a/b": 9, "c~d": 2]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try JSONPatch.apply(patch, to: a), b)
    }

    // MARK: - 10. Array reorder produces minimal moves, not a full replace

    func testArrayReorderProducesMoves() {
        // A keyed list reordered: [A,B,C,D] -> [D,A,B,C]. Same elements, new order.
        let a: JSONValue = ["list": [["id": "A"], ["id": "B"], ["id": "C"], ["id": "D"]]]
        let b: JSONValue = ["list": [["id": "D"], ["id": "A"], ["id": "B"], ["id": "C"]]]
        let patch = JSONPatch.diff(a, b)

        // Correctness gate.
        XCTAssertEqual(try? JSONPatch.apply(patch, to: a), b)

        // Minimality gate: the diff for the reordered list must be moves,
        // NOT a whole-array replace and NOT add+remove of every element.
        XCTAssertFalse(patch.isEmpty, "reorder should produce ops")
        XCTAssertTrue(patch.allSatisfy { $0.op == .move },
                      "reorder should be expressed as moves, got: \(patch.map(\.op))")
        // [D,A,B,C] from [A,B,C,D] is a single rotation: exactly one move suffices.
        XCTAssertEqual(patch.count, 1,
                       "rotating one element to the front should be 1 move, got \(patch.count): \(patch)")
        // And crucially: no replace of the array itself.
        XCTAssertFalse(patch.contains { $0.op == .replace && $0.path == "/list" },
                       "must not whole-array replace a reorder")
    }

    func testArrayReorderSwapTwoElements() {
        // Swap two adjacent keyed elements: [A,B,C] -> [B,A,C].
        let a: JSONValue = ["list": [["id": "A"], ["id": "B"], ["id": "C"]]]
        let b: JSONValue = ["list": [["id": "B"], ["id": "A"], ["id": "C"]]]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try? JSONPatch.apply(patch, to: a), b)
        XCTAssertTrue(patch.allSatisfy { $0.op == .move },
                      "swap should be moves, got: \(patch.map(\.op))")
        XCTAssertFalse(patch.contains { $0.op == .replace && $0.path == "/list" })
    }

    func testArrayReorderOfStrings() {
        // Scalars are their own identity key: ["x","y","z"] -> ["z","x","y"].
        let a: JSONValue = ["x", "y", "z"]
        let b: JSONValue = ["z", "x", "y"]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try? JSONPatch.apply(patch, to: a), b)
        XCTAssertTrue(patch.allSatisfy { $0.op == .move },
                      "string reorder should be moves, got: \(patch.map(\.op))")
    }

    func testArrayAppendIsNotReplace() {
        // Adding to the end of a keyed list should be an add, not a full replace.
        let a: JSONValue = [["id": "A"], ["id": "B"]]
        let b: JSONValue = [["id": "A"], ["id": "B"], ["id": "C"]]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try? JSONPatch.apply(patch, to: a), b)
        XCTAssertFalse(patch.contains { $0.op == .replace && $0.path == "" },
                       "append must not whole-array replace")
        XCTAssertTrue(patch.contains { $0.op == .add }, "append should emit an add")
    }

    func testArrayRemoveMiddleIsMinimal() {
        // Removing a middle element from a keyed list: minimal remove, not replace.
        let a: JSONValue = [["id": "A"], ["id": "B"], ["id": "C"]]
        let b: JSONValue = [["id": "A"], ["id": "C"]]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try? JSONPatch.apply(patch, to: a), b)
        XCTAssertFalse(patch.contains { $0.op == .replace && $0.path == "" })
        XCTAssertTrue(patch.contains { $0.op == .remove })
    }

    // MARK: - Extra coverage: nested element value changes inside arrays

    func testNestedElementChangeRecurses() throws {
        let a: JSONValue = ["rows": [["id": "A", "n": 1], ["id": "B", "n": 2]]]
        let b: JSONValue = ["rows": [["id": "A", "n": 1], ["id": "B", "n": 9]]]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try JSONPatch.apply(patch, to: a), b)
        // Should not be a whole-array replace; just the deep value changed.
        XCTAssertFalse(patch.contains { $0.op == .replace && $0.path == "/rows" })
    }

    func testTypeChangeIsReplace() throws {
        // Changing a value's type (object -> array) at a path is a replace.
        let a: JSONValue = ["x": ["a": 1]]
        let b: JSONValue = ["x": [1, 2]]
        let patch = JSONPatch.diff(a, b)
        XCTAssertEqual(try JSONPatch.apply(patch, to: a), b)
    }
}

// MARK: - Test support: seeded RNG + JSONValue generator

/// A small, deterministic `RandomNumberGenerator` (SplitMix64) so the property
/// test is fully reproducible across runs and machines.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Generates nested `JSONValue` trees: scalars, arrays, and objects. Object
/// keys are drawn from a small alphabet (including tricky keys with `/`, `~`,
/// and the empty string) so the diff/apply round-trip is exercised on the
/// RFC 6901 escaping edge cases too.
enum JSONValueGenerator {
    static let keyPool = ["a", "b", "c", "id", "x/y", "p~q", ""]

    static func random(using rng: inout SeededRNG, maxDepth: Int) -> JSONValue {
        // At depth 0 only emit scalars to bound the tree size.
        let pick = Int(rng.next() % (maxDepth <= 0 ? 4 : 6))
        switch pick {
        case 0: return .null
        case 1: return .bool(rng.next() % 2 == 0)
        case 2:
            // Integral numbers (round-trip exactly) drawn from a small range so
            // collisions/reuse happen, exercising move/copy detection.
            return .number(Double(Int(rng.next() % 7)))
        case 3:
            let strings = ["A", "B", "C", "D", "hi", ""]
            return .string(strings[Int(rng.next() % UInt64(strings.count))])
        case 4:
            let n = Int(rng.next() % 5)
            var arr: [JSONValue] = []
            arr.reserveCapacity(n)
            for _ in 0..<n { arr.append(random(using: &rng, maxDepth: maxDepth - 1)) }
            return .array(arr)
        default:
            let n = Int(rng.next() % 5)
            var obj: [String: JSONValue] = [:]
            for _ in 0..<n {
                let key = keyPool[Int(rng.next() % UInt64(keyPool.count))]
                obj[key] = random(using: &rng, maxDepth: maxDepth - 1)
            }
            return .object(obj)
        }
    }
}
