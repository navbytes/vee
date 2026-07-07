import SwiftUI
import VeeWidgetShared

// Presentation helpers shared by the Vee widgets: mapping the Foundation-only
// `SnapshotColor` to a SwiftUI `Color`, a dependency-free sparkline, and small
// building blocks (symbol glyph, freshness caption) used across families.

extension SnapshotColor {
    /// The SwiftUI color to render. Explicit RGBA maps directly; a named color
    /// resolves to a system color where we recognize it (preserving light/dark
    /// adaptivity), otherwise falls back to the primary label color.
    var swiftUIColor: Color {
        switch self {
        case .rgba(let r, let g, let b, let a):
            return Color(.sRGB,
                         red: Double(r) / 255, green: Double(g) / 255,
                         blue: Double(b) / 255, opacity: Double(a) / 255)
        case .named(let name):
            return Self.namedColors[name] ?? .primary
        }
    }

    private static let namedColors: [String: Color] = [
        "red": .red, "green": .green, "blue": .blue, "yellow": .yellow, "orange": .orange,
        "purple": .purple, "pink": .pink, "teal": .teal, "cyan": .cyan, "mint": .mint,
        "indigo": .indigo, "brown": .brown, "gray": .gray, "grey": .gray,
        "magenta": Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1),
        "black": .primary, "white": .primary, "clear": .clear,
        "labelcolor": .primary, "secondarylabelcolor": .secondary,
        "linkcolor": .blue, "controlaccentcolor": .accentColor, "accentcolor": .accentColor,
        "systemred": .red, "systemgreen": .green, "systemblue": .blue, "systemorange": .orange,
        "systemyellow": .yellow, "systemgray": .gray, "systempurple": .purple,
        "systempink": .pink, "systemteal": .teal, "systemindigo": .indigo
    ]
}

extension PluginSnapshot {
    /// The value's tint, or the primary label color when the plugin declared none.
    var valueColor: Color { color?.swiftUIColor ?? .primary }

    /// The SF Symbol color for the glyph (first `sfcolor`, else the value color).
    var glyphColor: Color { symbolColors?.first?.swiftUIColor ?? valueColor }
}

/// A tiny, dependency-free line chart for a `sparkline=` series. Normalizes the
/// series into the rect; a flat series draws a centered line.
struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let span = hi - lo
        func point(_ i: Int) -> CGPoint {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let norm = span == 0 ? 0.5 : (values[i] - lo) / span
            let y = rect.maxY - rect.height * CGFloat(norm)
            return CGPoint(x: x, y: y)
        }
        path.move(to: point(0))
        for i in 1..<values.count { path.addLine(to: point(i)) }
        return path
    }
}

/// A freshness caption ("2 min ago") that self-updates without a widget reload.
/// Shows nothing for an epoch-zero placeholder date.
struct FreshnessLabel: View {
    let updated: Date
    var stale: Bool = false

    var body: some View {
        if updated.timeIntervalSince1970 > 1 {
            Text(updated, style: .relative)
                .font(.caption2)
                .foregroundStyle(stale ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .lineLimit(1)
        }
    }
}
