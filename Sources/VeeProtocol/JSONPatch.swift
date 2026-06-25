import Foundation

/// A single RFC 6902 (JSON Patch) operation over a `JSONValue` document.
///
/// `path` and `from` are RFC 6901 JSON Pointers (e.g. `/children/0/props/title`,
/// or `""` for the whole document, or a trailing `/-` to append to an array).
/// The `op` discriminator selects which of `value`/`from` are required:
///   - add, replace, test  → require `value`
///   - remove              → only `path`
///   - move, copy          → require `from`
///
/// The algorithms (`diff`/`apply`) live in the separate `VeeJSONPatch` target;
/// this file is only the wire type so that `VeeProtocol` stays dependency-free.
public struct PatchOp: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case add, remove, replace, move, copy, test
    }

    public var op: Kind
    /// RFC 6901 JSON Pointer to the target location.
    public var path: String
    /// Operand for add/replace/test.
    public var value: JSONValue?
    /// Source pointer for move/copy.
    public var from: String?

    public init(op: Kind, path: String, value: JSONValue? = nil, from: String? = nil) {
        self.op = op
        self.path = path
        self.value = value
        self.from = from
    }

    // Explicit CodingKeys are unnecessary (names match the wire), but we omit
    // nil `value`/`from` so patches stay minimal and compare cleanly.
    private enum CodingKeys: String, CodingKey { case op, path, value, from }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(op, forKey: .op)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(from, forKey: .from)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        op = try c.decode(Kind.self, forKey: .op)
        path = try c.decode(String.self, forKey: .path)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value)
        from = try c.decodeIfPresent(String.self, forKey: .from)
    }
}

/// A patch is an ordered array of operations (apply in sequence). Type alias
/// kept distinct from `[PatchOp]` at call sites for readability.
public typealias JSONPatchDocument = [PatchOp]

/// Convenience constructors so host code and tests read clearly.
public extension PatchOp {
    static func add(_ path: String, _ value: JSONValue) -> PatchOp { .init(op: .add, path: path, value: value) }
    static func remove(_ path: String) -> PatchOp { .init(op: .remove, path: path) }
    static func replace(_ path: String, _ value: JSONValue) -> PatchOp { .init(op: .replace, path: path, value: value) }
    static func move(from: String, to path: String) -> PatchOp { .init(op: .move, path: path, from: from) }
    static func copy(from: String, to path: String) -> PatchOp { .init(op: .copy, path: path, from: from) }
    static func test(_ path: String, _ value: JSONValue) -> PatchOp { .init(op: .test, path: path, value: value) }
}

/// Errors thrown by `VeeJSONPatch.apply`. Declared here so callers across
/// targets can catch them without importing the algorithm target.
public enum JSONPatchError: Error, Equatable, Sendable {
    case invalidPointer(String)
    case pathNotFound(String)
    case testFailed(path: String)
    case typeMismatch(path: String)
    case arrayIndexOutOfBounds(path: String)
}
