import XCTest
@testable import VeeApp
import VeeMenu
import VeePreferences
import VeePluginFormat

/// D6: a raw/hostile plugin first line must never reach the menu bar
/// verbatim — see `StatusItemController.sanitizedTitleText`/`render(_:)`.
final class StatusItemTitleSanitizerPureFunctionTests: XCTestCase {
    func testStripsEmbeddedNULAndControlBytes() {
        let raw = "CPU\u{0000} 42%\u{0007}\u{001B}[31mred\u{001B}[0m"
        let clean = StatusItemController.sanitizedTitleText(raw)
        XCTAssertEqual(clean, "CPU 42%[31mred[0m")
        XCTAssertFalse(
            clean.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) },
            "no non-whitespace control character must survive"
        )
    }

    func testKeepsNormalWhitespaceEmojiAndRTLMarks() {
        let raw = "Hi \tthere 🎉 \u{200F}RTL"
        XCTAssertEqual(StatusItemController.sanitizedTitleText(raw), raw)
    }

    /// Regression: `CharacterSet.controlCharacters` covers Unicode Cc *and*
    /// Cf, and Cf also holds the ZWJ that joins compound emoji (e.g. a
    /// family emoji) — naively stripping anything in that set would corrupt
    /// otherwise-normal emoji, not just hostile input.
    func testKeepsZeroWidthJoinerInCompoundEmoji() {
        let family = "👨‍👩‍👧‍👦"   // four person emoji joined by U+200D ZWJ
        XCTAssertEqual(StatusItemController.sanitizedTitleText(family), family)
    }

    func testCapsAnEnormousTitleWithATrailingEllipsis() {
        let raw = String(repeating: "x", count: 10_000)
        let clean = StatusItemController.sanitizedTitleText(raw)
        XCTAssertEqual(clean.count, StatusItemController.maxTitleLength + 1, "capped length + the trailing ellipsis")
        XCTAssertTrue(clean.hasSuffix("…"))
        XCTAssertEqual(String(clean.dropLast()), String(raw.prefix(StatusItemController.maxTitleLength)))
    }

    func testShortWellBehavedTitleIsUntouched() {
        XCTAssertEqual(StatusItemController.sanitizedTitleText("CPU: 42%"), "CPU: 42%")
    }
}

/// Integration: proves the sanitizer is actually wired into the render path
/// (`render(_:)` → `frames` → the compact row's `attributedTitle`), not just
/// correct in isolation. Uses `CompactMenuBarController(attachesStatusItem:
/// false)` — the same `NSApplication`-free construction
/// `SearchAllPluginsAggregatorTests` uses — so this never touches
/// `NSStatusBar`/`NSApplication.shared`.
@MainActor
final class StatusItemTitleSanitizationRenderTests: XCTestCase {
    private final class RecordingHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
    }

    private func makeCompactPrefs() -> AppPreferences {
        let defaults = UserDefaults(suiteName: "vee-title-sanitize-tests-\(UUID().uuidString)")!
        let prefs = AppPreferences(defaults: defaults)
        prefs.compactMenuBar = true
        return prefs
    }

    private func renderedTitle(_ text: String) -> String? {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = StatusItemController(pluginName: "X", handler: RecordingHandler(), onRefresh: {}, prefs: prefs, compactController: compact)
        controller.render(ParsedOutput(titleLines: [TitleLine(text: text)]))
        defer { withExtendedLifetime(controller) {} }
        return compact.menu.items.first?.attributedTitle?.string
    }

    func testEmbeddedControlBytesStrippedFromTheRenderedTitle() {
        XCTAssertEqual(renderedTitle("CPU\u{0000}\u{0007} 42%"), "CPU 42%")
    }

    func testRunawayTitleCappedWithEllipsisInTheRenderedTitle() {
        let rendered = renderedTitle(String(repeating: "x", count: 10_000)) ?? ""
        XCTAssertEqual(rendered.count, StatusItemController.maxTitleLength + 1)
        XCTAssertTrue(rendered.hasSuffix("…"))
    }

    /// Regression: review found `sanitizedTitle` covered `frames` but not the
    /// `pluginName` fallback used when there are none — reachable for real
    /// via `swiftbar://setephemeralplugin?name=…`, whose `name` is
    /// attacker-controlled and unvalidated; an ephemeral with empty content
    /// has no title frames at all, so the status item fell back to the raw
    /// name. `setephemeralplugin` itself stays ungated (high-frequency
    /// automation call); sanitizing `pluginName` once at `init` — its single
    /// entry point — is the fix, and covers every fallback site at once.
    func testHostilePluginNameFallsBackSanitizedWhenThereAreNoTitleFrames() {
        let hostileName = "X\u{0000}\u{0007}" + String(repeating: "y", count: 10_000)
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let controller = StatusItemController(pluginName: hostileName, handler: RecordingHandler(), onRefresh: {}, prefs: prefs, compactController: compact)
        controller.render(ParsedOutput())   // no title lines ⇒ no frames ⇒ falls back to pluginName
        let rendered = compact.menu.items.first?.attributedTitle?.string ?? ""
        XCTAssertFalse(rendered.contains("\u{0000}"))
        XCTAssertFalse(rendered.contains("\u{0007}"))
        XCTAssertEqual(rendered.count, StatusItemController.maxTitleLength + 1, "capped length + the trailing ellipsis")
        XCTAssertTrue(rendered.hasSuffix("…"))
        withExtendedLifetime(controller) {}
    }
}
