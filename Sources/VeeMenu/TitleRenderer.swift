import AppKit
import VeePluginFormat

/// The status-bar presentation derived from a plugin's title lines: the
/// attributed text frames to display (cycled if more than one) and a leading
/// image, if the first title line declares one.
public struct StatusBarPresentation {
    public var frames: [NSAttributedString]
    public var image: NSImage?
}

/// Builds the status-item presentation from parsed title lines.
@MainActor
public enum TitleRenderer {
    public static func presentation(for titleLines: [TitleLine]) -> StatusBarPresentation {
        let menuBarFont = NSFont.menuBarFont(ofSize: 0)
        let frames = titleLines.map {
            AttributedTitleFactory.make(text: $0.text, params: $0.params, ansiRuns: $0.ansiRuns, defaultFont: menuBarFont)
        }
        let image = titleLines.first.flatMap { SymbolImageFactory.image(for: $0.params) }
        return StatusBarPresentation(frames: frames, image: image)
    }
}
