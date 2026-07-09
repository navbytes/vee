import AppKit
import SwiftUI
import VeeTrust

// MARK: - Category styling (icon + tint per catalog category)

public enum CategoryStyle {
    /// A rounded-square SF Symbol + tint for a category name (used in the
    /// sidebar and on card icon tiles).
    public static func symbol(for category: String) -> String {
        map[category.lowercased()]?.0 ?? "puzzlepiece.extension.fill"
    }

    public static func tint(for category: String) -> Color {
        map[category.lowercased()]?.1 ?? .accentColor
    }

    private static let map: [String: (String, Color)] = [
        "aws": ("cloud.fill", .orange),
        "cloud": ("cloud.fill", .cyan),
        "cryptocurrency": ("bitcoinsign.circle.fill", .orange),
        "dev": ("chevron.left.forwardslash.chevron.right", .purple),
        "development": ("chevron.left.forwardslash.chevron.right", .purple),
        "e-commerce": ("cart.fill", .pink),
        "email": ("envelope.fill", .blue),
        "environment": ("leaf.fill", .green),
        "finance": ("chart.line.uptrend.xyaxis", .green),
        "games": ("gamecontroller.fill", .indigo),
        "lifestyle": ("heart.fill", .pink),
        "music": ("music.note", .red),
        "network": ("network", .blue),
        "news": ("newspaper.fill", .brown),
        "science": ("atom", .teal),
        "sports": ("sportscourt.fill", .green),
        "system": ("cpu.fill", .blue),
        "time": ("clock.fill", .indigo),
        "tools": ("wrench.and.screwdriver.fill", .gray),
        "travel": ("airplane", .cyan),
        "tutorial": ("book.fill", .brown),
        "weather": ("cloud.sun.fill", .teal),
        "web": ("globe", .blue)
    ]
}

// MARK: - Trust level styling

public extension TrustLevel {
    var label: String {
        switch self {
        case .declared: return "Declared"
        case .partial: return "Incomplete"
        case .undeclared: return "Undeclared"
        }
    }
    var color: Color {
        switch self {
        case .declared: return .green
        case .partial: return .orange
        case .undeclared: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .declared: return "checkmark.shield.fill"
        case .partial: return "exclamationmark.shield.fill"
        case .undeclared: return "questionmark.circle"
        }
    }
}

// MARK: - Severity styling

public extension Severity {
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .high: return "exclamationmark.octagon.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }
    var word: String {
        switch self {
        case .high: return "Caution"
        case .medium: return "Review"
        case .low: return "Low"
        }
    }
}

// MARK: - Capability plain-language (verb-first, Chrome/Firefox style)

public extension Capability {
    var plainName: String {
        switch self {
        case .network: return "Connects to the internet"
        case .filesystem: return "Reads and writes files on your Mac"
        case .secrets: return "Uses stored credentials"
        case .exec: return "Runs other programs"
        case .clipboard: return "Reads or changes your clipboard"
        case .notifications: return "Shows notifications"
        }
    }
    var symbol: String {
        switch self {
        case .network: return "globe"
        case .filesystem: return "folder.fill"
        case .secrets: return "key.fill"
        case .exec: return "terminal.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notifications: return "bell.fill"
        }
    }
}

// MARK: - Layout tokens

/// Shared corner radii, so cards, callouts, and popovers stay visually
/// consistent instead of each view reaching for its own literal. Values match
/// what the views already used — this is a single source of truth, not a
/// restyle.
public enum Corner {
    /// Inset content surfaces, e.g. a debug output block.
    public static let surface: CGFloat = 8
    /// Tinted callout / warning boxes.
    public static let callout: CGFloat = 9
    /// Plugin cards in Discover.
    public static let card: CGFloat = 12
    /// Floating popovers (sparkline, control panels).
    public static let popover: CGFloat = 14
}

// MARK: - Visual foundation ("Calm instrument")

// Structure comes from neutral system surfaces + hairlines; the single brand
// accent (Ink) is reserved for identity/selection; saturated meaning-colors
// (trust green/amber/red, category tints) appear only where they mean something.

public extension Color {
    /// A light/dark sRGB-hex pair, resolved per appearance so a brand token gets
    /// automatic dark-mode / increased-contrast handling like a system color.
    init(lightHex: UInt, darkHex: UInt) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = dark ? darkHex : lightHex
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

/// The Vee palette. Neutral system surfaces carry structure; `brand` (Ink) is
/// identity-only — interactive controls keep the user's system accent color.
public enum Palette {
    public static let windowBG = Color(nsColor: .windowBackgroundColor)
    public static let raisedBG = Color(nsColor: .controlBackgroundColor)
    public static let insetBG = Color(nsColor: .underPageBackgroundColor)
    public static let hairline = Color(nsColor: .separatorColor)
    /// The one brand accent — "Ink".
    public static let brand = Color(lightHex: 0x4B5BD6, darkHex: 0x7C8CF0)
    public static let brandSoft = Color(lightHex: 0x4B5BD6, darkHex: 0x7C8CF0).opacity(0.12)
}

/// 8pt spacing grid, so views stop reaching for one-off literals.
public enum Space {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Semantic type roles. `metric` (rounded + monospaced digits) is the "Apple
/// dashboard" number treatment, shared by counts and widget values.
public enum TypeRole {
    public static let sectionTitle = Font.headline
    public static let cardTitle = Font.system(.body, weight: .semibold)
    public static let rowMeta = Font.subheadline
    public static let chip = Font.caption2.weight(.semibold)
    public static let metric = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
}

public extension View {
    /// The resting card treatment: raised fill + a hairline border (native depth
    /// comes from the hairline, not a drop shadow). On hover the border picks up
    /// the accent and only a whisper of shadow appears.
    func veeCardSurface(cornerRadius: CGFloat = Corner.card, hovering: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Palette.raisedBG))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(hovering ? Color.accentColor.opacity(0.55) : Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.06 : 0), radius: 4, y: 1)
    }
}

// MARK: - Reusable views

/// A small capsule showing an SF Symbol + short label in a tint. Filled — so its
/// weight is reserved for **state that matters** (trust level, error, severity).
/// For descriptive metadata (store, surface, freshness) use ``MetaChip`` instead.
public struct TrustChip: View {
    let symbol: String
    let label: String
    let tint: Color

    public init(symbol: String, label: String, tint: Color) {
        self.symbol = symbol
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A muted, *descriptive* chip: an SF Symbol + label with no fill, for metadata
/// (store name, surface, freshness) that shouldn't compete with a ``TrustChip``.
/// Splitting chips into these two weights is what de-clutters a busy card or row.
public struct MetaChip: View {
    let symbol: String
    let label: String
    var tint: Color

    public init(symbol: String, label: String, tint: Color = .secondary) {
        self.symbol = symbol
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(tint)
    }
}

/// A rounded-square icon tile tinted to a category, with a white SF Symbol.
public struct PluginTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    public init(symbol: String, tint: Color, size: CGFloat = 34) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: tint.opacity(0.35), radius: 3, y: 1)
    }
}

/// A masked secure field with an eye toggle to reveal — the standard idiom for
/// entering API tokens (SwiftUI's `SecureField` has no built-in reveal).
public struct RevealableSecureField: View {
    private let placeholder: String
    @Binding private var text: String
    @State private var revealed = false

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Hide" : "Show")
            .accessibilityLabel(revealed ? "Hide value" : "Show value")
        }
    }
}
