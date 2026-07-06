import AppKit

/// The subset of SwiftBar's `sfconfig=` JSON that Vee applies to an SF Symbol:
/// `scale` (small/medium/large) and `weight`. Palette/hierarchical colors are
/// already covered by the `sfcolor=` parameter. Unknown keys are ignored, and a
/// malformed value simply yields `nil` (the symbol renders with its defaults).
struct SFSymbolConfig: Decodable {
    var scale: String?
    var weight: String?

    static func parse(_ raw: String?) -> SFSymbolConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SFSymbolConfig.self, from: data)
    }

    var nsScale: NSImage.SymbolScale? {
        switch scale?.lowercased() {
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        default: return nil
        }
    }

    var nsWeight: NSFont.Weight? {
        switch weight?.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return nil
        }
    }
}
