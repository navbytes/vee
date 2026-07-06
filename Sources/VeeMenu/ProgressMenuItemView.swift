import AppKit

/// Pure geometry for the inline progress gauge — where the label, track, and
/// fill sit inside a menu row of a given width. Kept separate from the `NSView`
/// so the layout math is unit-testable without rendering.
public struct ProgressBarLayout: Equatable, Sendable {
    public var leadingInset: CGFloat
    public var trailingInset: CGFloat
    public var gap: CGFloat
    public var barWidth: CGFloat
    public var barHeight: CGFloat

    public init(barWidth: CGFloat, barHeight: CGFloat, leadingInset: CGFloat = 20, trailingInset: CGFloat = 12, gap: CGFloat = 10) {
        self.barWidth = barWidth
        self.barHeight = barHeight
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.gap = gap
    }

    /// The label, track (full bar), and fill (fraction of the bar) rects for the
    /// given bounds and completion. The track is trailing-anchored so it stays a
    /// fixed width as the menu (and this row) stretches; the label fills the rest.
    public func rects(in bounds: CGRect, fraction: CGFloat) -> (label: CGRect, track: CGRect, fill: CGRect) {
        let clamped = Swift.min(Swift.max(fraction, 0), 1)
        let trackX = bounds.maxX - trailingInset - barWidth
        let trackY = bounds.midY - barHeight / 2
        let track = CGRect(x: trackX, y: trackY, width: barWidth, height: barHeight)
        let fill = CGRect(x: trackX, y: trackY, width: barWidth * clamped, height: barHeight)
        let labelWidth = max(0, trackX - gap - leadingInset)
        let label = CGRect(x: leadingInset, y: bounds.minY, width: labelWidth, height: bounds.height)
        return (label, track, fill)
    }
}

/// A custom menu-row view that draws a plugin's `progress=` gauge inline: the
/// item's label on the left and a real, anti-aliased capsule bar on the right.
/// This is Vee's first *in-row* rich view (the sparkline/control popovers render
/// outside the `NSMenu`); it stays pure AppKit — no SwiftUI hosting — so the menu
/// remains native and leak-free. Decorative: it does not intercept clicks.
final class ProgressMenuItemView: NSView {
    private let title: NSAttributedString
    private let fraction: CGFloat
    private let fillColor: NSColor
    private let trackColor: NSColor
    private let layout: ProgressBarLayout

    init(title: NSAttributedString, fraction: Double, fillColor: NSColor, trackColor: NSColor, barWidth: CGFloat, barHeight: CGFloat) {
        self.title = title
        self.fraction = CGFloat(fraction)
        self.fillColor = fillColor
        self.trackColor = trackColor
        let layout = ProgressBarLayout(barWidth: barWidth, barHeight: barHeight)
        self.layout = layout
        let rowHeight = Swift.max(22, barHeight + 10)
        // Size to fit label + bar so the menu grows wide enough — a fixed width
        // would squeeze a long label (e.g. a 210pt hero bar) into truncation.
        let titleWidth = title.size().width.rounded(.up)
        let desiredWidth = layout.leadingInset + titleWidth + layout.gap + barWidth + layout.trailingInset
        super.init(frame: NSRect(x: 0, y: 0, width: Swift.max(240, desiredWidth), height: rowHeight))
        autoresizingMask = [.width] // still stretch if another row makes the menu wider
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let rects = layout.rects(in: bounds, fraction: fraction)

        // Label — vertically centered in its column, truncated if it collides
        // with the bar.
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(attributedString: title)
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        let textHeight = text.size().height
        let textRect = CGRect(x: rects.label.minX, y: rects.label.midY - textHeight / 2, width: rects.label.width, height: textHeight)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        // Track then fill, as rounded capsules.
        let radius = rects.track.height / 2
        trackColor.setFill()
        NSBezierPath(roundedRect: rects.track, xRadius: radius, yRadius: radius).fill()
        if rects.fill.width > 0 {
            fillColor.setFill()
            NSBezierPath(roundedRect: rects.fill, xRadius: radius, yRadius: radius).fill()
        }
    }
}
