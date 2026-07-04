import Foundation

/// A color parsed from a plugin's `color=` / `sfcolor=` parameter. Kept
/// AppKit-free (no `NSColor`) so the parser stays pure; `VeeMenu` converts.
public enum VeeColor: Equatable, Sendable {
    /// A CSS/AppKit color name such as `red`, `blue`, `labelColor` (lowercased).
    case named(String)
    /// An explicit RGBA color (each channel 0–255).
    case rgb(r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    /// Parses `red`, `#f00`, `#ff0000`, or `#ff0000ff`. Returns `nil` if empty
    /// or a malformed hex literal.
    public static func parse(_ string: String) -> VeeColor? {
        let t = string.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("#") { return parseHex(String(t.dropFirst())) }
        return .named(t.lowercased())
    }

    private static func parseHex(_ hex: String) -> VeeColor? {
        func b(_ s: Substring) -> UInt8? { UInt8(s, radix: 16) }
        let chars = Array(hex)
        switch chars.count {
        case 3:
            guard let r = b("\(chars[0])\(chars[0])"[...]),
                  let g = b("\(chars[1])\(chars[1])"[...]),
                  let bl = b("\(chars[2])\(chars[2])"[...]) else { return nil }
            return .rgb(r: r, g: g, b: bl, a: 255)
        case 6, 8:
            func pair(_ i: Int) -> UInt8? { b(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 2)]) }
            guard let r = pair(0), let g = pair(2), let bl = pair(4) else { return nil }
            let a = chars.count == 8 ? pair(6) : 255
            guard let alpha = a else { return nil }
            return .rgb(r: r, g: g, b: bl, a: alpha)
        default:
            return nil
        }
    }
}
