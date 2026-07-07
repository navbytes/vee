import Foundation

/// A color the app publishes for the widget to draw (a title tint, an SF Symbol
/// color). Deliberately mirrors `VeePluginFormat.VeeColor` but is redeclared
/// here so `VeeWidgetShared` stays Foundation-only and dependency-free — the
/// sandboxed widget extension links it and must pull in almost nothing. The app
/// maps `VeeColor` → `SnapshotColor` at publish time.
///
/// Encoded as a single compact string (`"red"` or `"#rrggbbaa"`) so the snapshot
/// JSON stays small and human-readable, and so the format can round-trip through
/// the same hex grammar the plugin parser already uses.
public enum SnapshotColor: Equatable, Sendable {
    /// A CSS/AppKit color name such as `red` or `labelcolor` (stored lowercased).
    case named(String)
    /// An explicit RGBA color (each channel 0–255).
    case rgba(r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    /// Parses `red`, `#f00`, `#ff0000`, or `#ff0000ff`. Returns `nil` for an
    /// empty string or a malformed hex literal.
    public static func parse(_ string: String) -> SnapshotColor? {
        let t = string.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("#") { return parseHex(String(t.dropFirst())) }
        return .named(t.lowercased())
    }

    private static func parseHex(_ hex: String) -> SnapshotColor? {
        func byte(_ s: Substring) -> UInt8? { UInt8(s, radix: 16) }
        let chars = Array(hex)
        switch chars.count {
        case 3:
            guard let r = byte("\(chars[0])\(chars[0])"[...]),
                  let g = byte("\(chars[1])\(chars[1])"[...]),
                  let b = byte("\(chars[2])\(chars[2])"[...]) else { return nil }
            return .rgba(r: r, g: g, b: b, a: 255)
        case 6, 8:
            func pair(_ i: Int) -> UInt8? {
                byte(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 2)])
            }
            guard let r = pair(0), let g = pair(2), let b = pair(4) else { return nil }
            let a = chars.count == 8 ? pair(6) : 255
            guard let alpha = a else { return nil }
            return .rgba(r: r, g: g, b: b, a: alpha)
        default:
            return nil
        }
    }

    /// The compact string form used for encoding and round-tripping.
    public var stringValue: String {
        switch self {
        case .named(let name):
            return name
        case .rgba(let r, let g, let b, let a):
            return String(format: "#%02x%02x%02x%02x", Int(r), Int(g), Int(b), Int(a))
        }
    }
}

extension SnapshotColor: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // A stored value is always well-formed, but fall back to a named color so
        // a hand-edited or future value never fails the whole snapshot decode.
        self = SnapshotColor.parse(raw) ?? .named(raw.lowercased())
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
