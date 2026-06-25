import Foundation

/// A fully-typed, `Codable`, `Sendable` representation of any JSON value.
///
/// `RenderNode` props and JSON Patch operands are heterogeneous, so we model
/// them with this enum rather than `[String: Any]`. It encodes/decodes to
/// natural JSON (no type tags) and supports value-equality, which the JSON
/// Patch `diff`/`apply` and `test` op rely on.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    /// All JSON numbers are stored as `Double`. JSON has a single number type;
    /// integers round-trip exactly within ±2^53. Use `intValue` for convenience.
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not a valid JSON value")
        }
    }

    // MARK: Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:          try container.encodeNil()
        case .bool(let b):   try container.encode(b)
        case .number(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Ergonomic accessors

public extension JSONValue {
    var isNull: Bool { if case .null = self { return true }; return false }

    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }

    var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }

    /// Returns the number as `Int` when it is integral and in range; else nil.
    var intValue: Int? {
        guard case .number(let d) = self, d.rounded() == d,
              d <= Double(Int.max), d >= Double(Int.min) else { return nil }
        return Int(d)
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }

    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// Member access for object values, e.g. `node["title"]?.stringValue`.
    subscript(key: String) -> JSONValue? {
        guard case .object(let o) = self else { return nil }
        return o[key]
    }
}

// MARK: - Literal conformances (author render trees inline in tests/host code)

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}
extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
