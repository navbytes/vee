import AppKit
import VeePluginFormat

/// Builds an `NSAttributedString` for a menu/title line from its text, params,
/// and ANSI style runs.
public enum AttributedTitleFactory {
    /// - Parameter defaultFont: font to use when the line declares none (menu
    ///   items use the menu font; status-bar titles use the menu-bar font).
    public static func make(text: String, params: LineParams, ansiRuns: [AnsiRun], defaultFont: NSFont) -> NSAttributedString {
        let baseFont = font(params: params, fallback: defaultFont)

        // `md=true`: render the text as (inline) Markdown.
        if params.swiftbar.markdown == true, let markdown = markdownAttributed(text, font: baseFont) {
            return finalize(markdown, params: params, font: baseFont)
        }

        // Apply `length` truncation up front (on the visible text).
        var display = text
        var runs = ansiRuns
        if let length = params.length, display.count > length {
            display = String(display.prefix(length)) + "…"
            runs = runs.compactMap { clamp($0, to: length) }
        }

        let baseColor = params.color.flatMap(ColorResolver.nsColor(for:)) ?? .labelColor

        let attributed = NSMutableAttributedString(string: display, attributes: [
            .font: baseFont,
            .foregroundColor: baseColor
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
            if let bg = run.background.flatMap(ColorResolver.nsColor(for:)) {
                attributed.addAttribute(.backgroundColor, value: bg, range: nsRange)
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
        return finalize(attributed, params: params, font: baseFont)
    }

    /// Applies `symbolize` (inline SF Symbols) then appends a `badge`.
    private static func finalize(_ base: NSAttributedString, params: LineParams, font: NSFont) -> NSAttributedString {
        var result = base
        if params.swiftbar.symbolize == true {
            result = symbolized(result, font: font)
        }
        return withBadge(result, params: params, font: font)
    }

    /// Appends a `badge=` value as a subtle trailing chip.
    private static func withBadge(_ base: NSAttributedString, params: LineParams, font: NSFont) -> NSAttributedString {
        guard let badge = params.swiftbar.badge, !badge.isEmpty else { return base }
        let result = NSMutableAttributedString(attributedString: base)
        result.append(NSAttributedString(string: "  \(badge)", attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return result
    }

    // Compile-time-constant pattern; cannot fail at runtime.
    // swiftlint:disable:next force_try
    private static let symbolPattern = try! NSRegularExpression(pattern: ":([A-Za-z0-9._-]+):", options: [])

    /// Replaces `:sf.symbol.name:` tokens with inline SF Symbol attachments.
    private static func symbolized(_ base: NSAttributedString, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: base)
        let matches = symbolPattern.matches(in: result.string, range: NSRange(location: 0, length: result.length))
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        // Replace right-to-left so earlier ranges stay valid.
        for match in matches.reversed() {
            let name = (result.string as NSString).substring(with: match.range(at: 1))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
            image.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = image
            result.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
        }
        return result
    }

    private static func markdownAttributed(_ text: String, font: NSFont) -> NSAttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? NSAttributedString(markdown: text, options: options) else { return nil }
        // Markdown carries its own fonts; normalize to the menu font size while
        // preserving bold/italic traits.
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let sized = NSFontManager.shared.font(withFamily: font.familyName ?? "System", traits: traits, weight: 5, size: font.pointSize) ?? font
            result.addAttribute(.font, value: sized, range: range)
        }
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        return result
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
