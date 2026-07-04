import AppKit
import VeePluginFormat

/// Resolves a parsed `VeeColor` to an `NSColor`. Supports explicit RGBA, a set
/// of common CSS-style names, and AppKit semantic colors (`labelColor`, etc.).
public enum ColorResolver {
    public static func nsColor(for color: VeeColor) -> NSColor? {
        switch color {
        case .rgb(let r, let g, let b, let a):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
        case .named(let name):
            return named[name.replacingOccurrences(of: " ", with: "")]
        }
    }

    private static let named: [String: NSColor] = [
        "black": .black, "white": .white, "red": .systemRed, "green": .systemGreen,
        "blue": .systemBlue, "yellow": .systemYellow, "orange": .systemOrange,
        "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown,
        "gray": .systemGray, "grey": .systemGray, "cyan": .systemCyan, "teal": .systemTeal,
        "indigo": .systemIndigo, "magenta": .magenta, "clear": .clear,
        // AppKit semantic colors (dynamic, adapt to appearance)
        "labelcolor": .labelColor, "secondarylabelcolor": .secondaryLabelColor,
        "tertiarylabelcolor": .tertiaryLabelColor, "linkcolor": .linkColor,
        "controlaccentcolor": .controlAccentColor,
    ]
}
