import AppKit
import VeePluginFormat

/// Builds an `NSAttributedString` for a menu/title line from its text, params,
/// and ANSI style runs.
public enum AttributedTitleFactory {
    /// - Parameter defaultFont: font to use when the line declares none (menu
    ///   items use the menu font; status-bar titles use the menu-bar font).
    public static func make(text: String, params: LineParams, ansiRuns: [AnsiRun], defaultFont: NSFont) -> NSAttributedString {
        // Apply `length` truncation up front (on the visible text).
        var display = text
        var runs = ansiRuns
        if let length = params.length, display.count > length {
            display = String(display.prefix(length)) + "…"
            runs = runs.compactMap { clamp($0, to: length) }
        }

        let baseFont = font(params: params, fallback: defaultFont)
        let baseColor = params.color.flatMap(ColorResolver.nsColor(for:)) ?? .labelColor

        let attributed = NSMutableAttributedString(string: display, attributes: [
            .font: baseFont,
            .foregroundColor: baseColor,
        ])

        let chars = Array(display)
        for run in runs {
            let lower = max(0, run.range.lowerBound)
            let upper = min(chars.count, run.range.upperBound)
            guard lower < upper else { continue }
            let nsRange = NSRange(location: lower, length: upper - lower)

            if let fg = run.foreground.flatMap(ColorResolver.nsColor(for:)) {
                attributed.addAttribute(.foregroundColor, value: fg, range: nsRange)
            }
            if run.underline {
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }
            if run.bold || run.italic {
                var traits: NSFontTraitMask = []
                if run.bold { traits.insert(.boldFontMask) }
                if run.italic { traits.insert(.italicFontMask) }
                let styled = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
                attributed.addAttribute(.font, value: styled, range: nsRange)
            }
        }
        return attributed
    }

    private static func font(params: LineParams, fallback: NSFont) -> NSFont {
        let size = params.size.map { CGFloat($0) } ?? fallback.pointSize
        if let name = params.font, let named = NSFont(name: name, size: size) {
            return named
        }
        if let size = params.size {
            return NSFont.systemFont(ofSize: CGFloat(size))
        }
        return fallback
    }

    private static func clamp(_ run: AnsiRun, to length: Int) -> AnsiRun? {
        guard run.range.lowerBound < length else { return nil }
        var r = run
        r.range = run.range.lowerBound..<min(run.range.upperBound, length)
        return r
    }
}
