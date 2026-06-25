#if canImport(AppKit)
import XCTest
import AppKit
@testable import VeeApp
import VeeProtocol

/// UI/accessibility hardening suite (AUDIT.md §6/§7/§8): PERF-1 (icon LRU cache),
/// UI-1 (Markdown → attributed fallback), UI-2 (shortcut token → glyph + per-row
/// suppression), UX-2 (accessibility composition), UX-5 (toast seam), UX-7 is
/// verified manually (the show animation is not unit-testable).
///
/// These exercise the *pure* logic factored out of the AppKit views — the
/// translator, the cache, the Markdown fallback, the suppression rule — plus the
/// toast-seam contract. The NSView rendering itself is verified by eye.
@MainActor
final class UIHardeningTests: XCTestCase {

    // MARK: - UI-2: shortcut token → glyph translation (pure)

    func testShortcutGlyphTranslatesKnownTokens() {
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "cmd"), "⌘")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "command"), "⌘")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "enter"), "⏎")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "return"), "⏎")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "opt"), "⌥")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "option"), "⌥")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "shift"), "⇧")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "ctrl"), "⌃")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "control"), "⌃")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "space"), "Space")
    }

    func testShortcutGlyphIsCaseInsensitiveAndPassesThroughUnknown() {
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "CMD"), "⌘")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "Enter"), "⏎")
        // A single unknown letter uppercases ("k" → "K"); a longer unknown token
        // is capitalized rather than mangled.
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "k"), "K")
        XCTAssertEqual(ShortcutGlyphs.glyph(for: "f5"), "F5")
    }

    func testShortcutDisplayJoinsGlyphs() {
        XCTAssertEqual(ShortcutGlyphs.display(for: "cmd+enter"), "⌘⏎")
        XCTAssertEqual(ShortcutGlyphs.display(for: "shift+opt+space"), "⇧⌥Space")
        XCTAssertEqual(ShortcutGlyphs.display(for: "cmd+k"), "⌘K")
        XCTAssertEqual(ShortcutGlyphs.display(for: nil), "")
        XCTAssertEqual(ShortcutGlyphs.display(for: ""), "")
    }

    func testShortcutCapsTokenizeAndTrim() {
        XCTAssertEqual(ShortcutGlyphs.caps(for: "cmd+enter"), ["⌘", "⏎"])
        // Whitespace + empty subsequences are dropped.
        XCTAssertEqual(ShortcutGlyphs.caps(for: " cmd + enter "), ["⌘", "⏎"])
        XCTAssertEqual(ShortcutGlyphs.caps(for: "cmd++enter"), ["⌘", "⏎"])
        XCTAssertEqual(ShortcutGlyphs.caps(for: nil), [])
    }

    func testShortcutSpokenPhraseForVoiceOver() {
        XCTAssertEqual(ShortcutGlyphs.spokenPhrase(for: "cmd+enter"), "Command, Return")
        XCTAssertEqual(ShortcutGlyphs.spokenPhrase(for: "cmd+k"), "Command, K")
        XCTAssertEqual(ShortcutGlyphs.spokenPhrase(for: nil), "")
    }

    func testCanonicalCollapsesSynonyms() {
        // Synonym spellings/case collapse to the same canonical key so the
        // footer-primary suppression matches regardless of how a plugin spelled it.
        XCTAssertEqual(ShortcutGlyphs.canonical("cmd+enter"),
                       ShortcutGlyphs.canonical("command+return"))
        XCTAssertEqual(ShortcutGlyphs.canonical("RETURN"),
                       ShortcutGlyphs.canonical("enter"))
        XCTAssertEqual(ShortcutGlyphs.canonical(nil), "")
    }

    // MARK: - UI-2: per-row shortcut suppression (pure)

    func testRowShortcutSuppressesFooterPrimary() {
        let footerPrimary = ShortcutGlyphs.canonical("return")
        // A bare Return (in any spelling) is suppressed — the footer already shows ↩.
        XCTAssertEqual(LauncherRowView.shortcutCaps(for: "return", suppressedCanonical: footerPrimary), [])
        XCTAssertEqual(LauncherRowView.shortcutCaps(for: "enter", suppressedCanonical: footerPrimary), [])
        // A non-primary shortcut renders its caps.
        XCTAssertEqual(LauncherRowView.shortcutCaps(for: "cmd+enter", suppressedCanonical: footerPrimary),
                       ["⌘", "⏎"])
        // No shortcut → no caps.
        XCTAssertEqual(LauncherRowView.shortcutCaps(for: nil, suppressedCanonical: footerPrimary), [])
    }

    func testRoleDescriptionDistinguishesAppsFromCommands() {
        let app = ListItemViewModel(id: "safari", title: "Safari",
                                    icon: "/Applications/Safari.app")
        let command = ListItemViewModel(id: "clip", title: "Clipboard History",
                                        icon: "doc.on.clipboard")
        XCTAssertEqual(AppKitLauncherWindow.roleDescription(for: app), "application")
        XCTAssertEqual(AppKitLauncherWindow.roleDescription(for: command), "command")
    }

    // MARK: - PERF-1: icon LRU cache hit / evict behavior (pure, value type)

    func testIconCacheHitReturnsStoredValue() {
        let cache = IconLRUCache<Int>(capacity: 4)
        XCTAssertNil(cache.value(forKey: "/a"))
        cache.setValue(1, forKey: "/a")
        XCTAssertEqual(cache.value(forKey: "/a"), 1, "a stored key is a cache hit")
        XCTAssertEqual(cache.count, 1)
        // Re-setting an existing key replaces in place, not grows.
        cache.setValue(2, forKey: "/a")
        XCTAssertEqual(cache.value(forKey: "/a"), 2)
        XCTAssertEqual(cache.count, 1)
    }

    func testIconCacheEvictsLeastRecentlyUsed() {
        let cache = IconLRUCache<Int>(capacity: 2)
        cache.setValue(1, forKey: "/a")
        cache.setValue(2, forKey: "/b")
        // Touch "/a" so "/b" becomes the LRU; inserting "/c" evicts "/b".
        _ = cache.value(forKey: "/a")
        cache.setValue(3, forKey: "/c")
        XCTAssertEqual(cache.count, 2, "capacity is respected")
        XCTAssertEqual(cache.value(forKey: "/a"), 1, "recently-used key survives")
        XCTAssertEqual(cache.value(forKey: "/c"), 3, "newest key present")
        XCTAssertNil(cache.value(forKey: "/b"), "least-recently-used key evicted")
    }

    func testIconCacheEvictsInInsertionOrderWithoutTouches() {
        let cache = IconLRUCache<Int>(capacity: 2)
        cache.setValue(1, forKey: "/a")
        cache.setValue(2, forKey: "/b")
        cache.setValue(3, forKey: "/c")   // no touches → "/a" (oldest) evicted
        XCTAssertNil(cache.value(forKey: "/a"))
        XCTAssertEqual(cache.value(forKey: "/b"), 2)
        XCTAssertEqual(cache.value(forKey: "/c"), 3)
    }

    /// The production resolver memoizes a real file-path icon: a second call for
    /// the same path returns the identical cached `NSImage` instance (no second
    /// Launch-Services hit). Uses a path guaranteed to exist on macOS.
    func testResolveIconCachesFilePathResult() throws {
        let path = "/System/Library/CoreServices/Finder.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Finder.app not present at the expected path")
        }
        let (first, firstIsReal) = LauncherRowView.resolveIcon(path)
        let (second, secondIsReal) = LauncherRowView.resolveIcon(path)
        XCTAssertTrue(firstIsReal, "a real file path resolves to a real icon")
        XCTAssertTrue(secondIsReal)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "the second resolve returns the cached instance")
        XCTAssertNotNil(LauncherRowView.iconCache.value(forKey: path),
                        "the path is present in the process icon cache")
    }

    func testResolveIconFallsBackForUnknownHint() {
        // An empty/nil hint and a non-path, non-symbol hint both yield the
        // fallback glyph and isRealIcon == false (not a file icon).
        XCTAssertFalse(LauncherRowView.resolveIcon(nil).1)
        XCTAssertFalse(LauncherRowView.resolveIcon("").1)
        // A missing absolute path must not be treated as a real icon.
        XCTAssertFalse(LauncherRowView.resolveIcon("/no/such/path/zzz.app").1)
    }

    func testResolveIconResolvesSFSymbol() {
        let (image, isReal) = LauncherRowView.resolveIcon("magnifyingglass")
        XCTAssertNotNil(image, "a valid SF Symbol name resolves to an image")
        XCTAssertFalse(isReal, "an SF Symbol is not a real file icon")
    }

    // MARK: - UI-1: Markdown → attributed, with plain-text fallback (pure)

    func testMarkdownRendersBoldAsAttributedNotLiteral() {
        let font = NSFont.systemFont(ofSize: 13)
        let result = AppKitLauncherWindow.attributedMarkdown("**bold** text", baseFont: font)
        // The literal asterisks are gone — the markup was interpreted.
        XCTAssertFalse(result.string.contains("**"), "markdown syntax should be parsed away")
        XCTAssertTrue(result.string.contains("bold"))
        XCTAssertTrue(result.string.contains("text"))
        XCTAssertGreaterThan(result.length, 0)
    }

    func testMarkdownEmptyStringYieldsEmptyAttributed() {
        let font = NSFont.systemFont(ofSize: 13)
        let result = AppKitLauncherWindow.attributedMarkdown("", baseFont: font)
        XCTAssertEqual(result.string, "", "empty markdown → empty body")
    }

    func testMarkdownPlainTextSurvivesAndCarriesBaseFont() {
        // Text with no markup round-trips as plain text with the body font + label
        // color applied (the fallback baseline), never dropped.
        let font = NSFont.systemFont(ofSize: 13)
        let result = AppKitLauncherWindow.attributedMarkdown("just plain text", baseFont: font)
        XCTAssertEqual(result.string, "just plain text")
        var range = NSRange(location: 0, length: 0)
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor, "fallback applies the label color")
        let appliedFont = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        XCTAssertNotNil(appliedFont, "a font is always applied so the body never renders fontless")
    }

    func testMarkdownHeadingAndListAreParsed() {
        let font = NSFont.systemFont(ofSize: 13)
        let result = AppKitLauncherWindow.attributedMarkdown("# Title\n\n- one\n- two", baseFont: font)
        XCTAssertFalse(result.string.contains("#"), "heading hashes are interpreted away")
        XCTAssertTrue(result.string.contains("Title"))
        XCTAssertTrue(result.string.contains("one"))
        XCTAssertTrue(result.string.contains("two"))
    }

    // MARK: - UX-5: toast seam contract

    func testToastSeamDefaultIsNoOpForSpies() {
        // A presenter that doesn't implement presentToast still compiles and the
        // default no-op simply does nothing (no crash, no state change).
        let spy = ToastlessSpyPresenter()
        spy.presentToast(style: .failure, title: "Network error", message: "Timed out")
        XCTAssertNil(spy.lastRoot, "the default no-op toast touches no other state")
    }

    func testToastSeamSpyCanCaptureCalls() {
        // A presenter that overrides presentToast receives the call verbatim,
        // proving the protocol carries the capability the coordinator will use.
        let spy = ToastCapturingSpyPresenter()
        spy.presentToast(style: .success, title: "Copied", message: nil)
        spy.presentToast(style: .info, title: "Heads up", message: "FYI")
        XCTAssertEqual(spy.toasts.count, 2)
        XCTAssertEqual(spy.toasts[0].style, .success)
        XCTAssertEqual(spy.toasts[0].title, "Copied")
        XCTAssertNil(spy.toasts[0].message)
        XCTAssertEqual(spy.toasts[1].style, .info)
        XCTAssertEqual(spy.toasts[1].message, "FYI")
    }

    func testToastBannerStyleAppearanceMapping() {
        // Each style maps to a distinct symbol + tint (UX-5 styling contract).
        XCTAssertEqual(ToastBannerView.appearance(for: .success).symbol, "checkmark.circle.fill")
        XCTAssertEqual(ToastBannerView.appearance(for: .success).tint, .systemGreen)
        XCTAssertEqual(ToastBannerView.appearance(for: .failure).symbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(ToastBannerView.appearance(for: .failure).tint, .systemRed)
        XCTAssertEqual(ToastBannerView.appearance(for: .info).symbol, "info.circle.fill")
        XCTAssertEqual(ToastBannerView.appearance(for: .info).tint, .systemBlue)
    }
}

// MARK: - Test doubles (toast seam)

/// A presenter that does NOT override `presentToast` — exercises the protocol's
/// default no-op so existing conformers stay source-compatible (UX-5).
private final class ToastlessSpyPresenter: LauncherWindowPresenting {
    private(set) var lastRoot: RootViewModel?
    func setRootViewModel(_ root: RootViewModel?) { lastRoot = root }
    func showLauncher() {}
    func hideLauncher() {}
}

/// A presenter that overrides `presentToast` to record calls.
private final class ToastCapturingSpyPresenter: LauncherWindowPresenting {
    struct Toast { let style: ToastStyle; let title: String; let message: String? }
    private(set) var toasts: [Toast] = []
    func setRootViewModel(_ root: RootViewModel?) {}
    func showLauncher() {}
    func hideLauncher() {}
    func presentToast(style: ToastStyle, title: String, message: String?) {
        toasts.append(Toast(style: style, title: title, message: message))
    }
}
#endif
