import AppKit
import VeePluginFormat

/// Resolves one chart segment to the `NSColor` the menu draws it with.
///
/// A plugin's own `chartcolors=` entry wins; otherwise the segment takes its
/// `ChartPalette` slot, and because each slot is a *pair* selected per surface
/// (not one color flipped), the result is a dynamic `NSColor` that re-resolves
/// when the system appearance changes — the menu is drawn in whichever
/// appearance is active when it opens.
public enum ChartColorResolver {
    public static func nsColor(for chart: ChartParams, at index: Int) -> NSColor {
        // An explicit override, when it names a color we understand. A
        // malformed one already became a hole at parse time, but an unknown
        // *name* survives parsing (`VeeColor.parse` accepts any bare word), so
        // it lands here and falls through to the palette rather than rendering
        // the segment invisible.
        if let override = chart.colorOverride(at: index),
           let resolved = ColorResolver.nsColor(for: override) {
            return resolved
        }
        return dynamic(
            light: chart.paletteColor(at: index, surface: .light),
            dark: chart.paletteColor(at: index, surface: .dark)
        )
    }

    /// Wraps a palette slot's light/dark steps in an appearance-aware `NSColor`.
    private static func dynamic(light: VeeColor, dark: VeeColor) -> NSColor {
        let lightColor = ColorResolver.nsColor(for: light) ?? .controlAccentColor
        let darkColor = ColorResolver.nsColor(for: dark) ?? .controlAccentColor
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }
}
