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

// MARK: - Reusable views

/// A small capsule showing an SF Symbol + short label in a tint.
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
