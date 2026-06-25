import XCTest
@testable import VeeApp
import VeeServices

/// Tests for the Settings feature's PURE, testable logic (R2 settings work):
///   • `HotkeyEventMapper` — the synthetic-event → `HotkeyChord` mapping and the
///     key-cap display string (no real `NSEvent` needed).
///   • `SettingsModel` — chord encode/decode + `UserDefaults` persistence against
///     a fresh suite, defaults, blocklist, history clamping, and change callbacks.
///   • `InMemoryTokenStore` — the in-VeeApp `TokenStoring` fake.
///
/// The AppKit shells (`HotkeyRecorderView`, `SettingsWindowController`) are
/// verified manually; only the logic they delegate to is asserted here.
final class SettingsTests: XCTestCase {

    // MARK: - HotkeyEventMapper (pure NSEvent → HotkeyChord)

    /// A complete chord (a real key + at least one modifier) maps through.
    func testMapperBuildsChordFromKeyPlusModifiers() {
        // ⌘ + Space (keyCode 49) using AppKit's raw command-flag bit.
        let event = RawKeyEvent(keyCode: 49, rawModifierFlags: HotkeyEventMapper.FlagBits.command)
        let chord = HotkeyEventMapper.chord(from: event)
        XCTAssertEqual(chord, HotkeyChord(keyCode: 49, modifiers: .command))
    }

    /// All four modifiers combine into the full option set.
    func testMapperCombinesAllModifiers() {
        let raw = HotkeyEventMapper.FlagBits.command
            | HotkeyEventMapper.FlagBits.option
            | HotkeyEventMapper.FlagBits.control
            | HotkeyEventMapper.FlagBits.shift
        let chord = HotkeyEventMapper.chord(from: RawKeyEvent(keyCode: 0, rawModifierFlags: raw))
        XCTAssertEqual(chord?.modifiers, [.command, .option, .control, .shift])
        XCTAssertEqual(chord?.keyCode, 0)
    }

    /// Non-modifier bits (caps lock, function, device-dependent) are ignored, so
    /// a chord with stray flags still maps to exactly the intended modifiers.
    func testMapperIgnoresNonModifierFlagBits() {
        // Option bit + caps-lock bit (1 << 16) + a device-dependent high bit.
        let raw = HotkeyEventMapper.FlagBits.option | (1 << 16) | (1 << 24)
        let mods = HotkeyEventMapper.modifiers(fromRawFlags: raw)
        XCTAssertEqual(mods, .option, "only the recognized modifier bits survive")
    }

    /// A bare key with NO modifiers is rejected (would hijack normal typing).
    func testMapperRejectsBareKeyWithoutModifiers() {
        let event = RawKeyEvent(keyCode: 49, rawModifierFlags: 0)
        XCTAssertNil(HotkeyEventMapper.chord(from: event))
    }

    /// A modifier-only press (the key code is itself a modifier) is rejected —
    /// there's no "real" key yet. Left-Command is keyCode 55.
    func testMapperRejectsModifierOnlyPress() {
        let event = RawKeyEvent(keyCode: 55, rawModifierFlags: HotkeyEventMapper.FlagBits.command)
        XCTAssertNil(HotkeyEventMapper.chord(from: event), "a lone modifier key is not a chord")
    }

    /// The display string renders modifiers in canonical order + the key glyph.
    func testDisplayStringRendersGlyphsInCanonicalOrder() {
        let chord = HotkeyChord(keyCode: 49, modifiers: [.command, .option, .control, .shift])
        // Canonical Cocoa order is ⌃⌥⇧⌘, then the key.
        XCTAssertEqual(HotkeyEventMapper.displayString(for: chord), "⌃⌥⇧⌘Space")

        let letter = HotkeyChord(keyCode: 11, modifiers: .command) // keyCode 11 == B
        XCTAssertEqual(HotkeyEventMapper.displayString(for: letter), "⌘B")

        let unknown = HotkeyChord(keyCode: 999, modifiers: .control)
        XCTAssertEqual(HotkeyEventMapper.displayString(for: unknown), "⌃key 999")
    }

    // MARK: - SettingsModel persistence (fresh UserDefaults suite)

    /// A fresh, isolated defaults suite per test so persistence is deterministic
    /// and never touches the user's real "com.vee.launcher" suite.
    private func freshDefaults(_ function: String = #function) -> (UserDefaults, String) {
        let suite = "com.vee.launcher.test.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @MainActor
    func testDefaultsWhenSuiteIsEmpty() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = SettingsModel(defaults: defaults)
        XCTAssertEqual(model.hotkey, SettingsModel.defaultHotkey)
        XCTAssertEqual(model.historySize, SettingsModel.defaultHistorySize)
        XCTAssertEqual(model.blocklist, [])
    }

    @MainActor
    func testHotkeyEncodeDecodeRoundTripsThroughDefaults() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let chord = HotkeyChord(keyCode: 17, modifiers: [.command, .shift]) // ⌘⇧T
        do {
            let model = SettingsModel(defaults: defaults)
            model.updateHotkey(chord)
        }
        // A brand-new model reading the same suite decodes the same chord
        // (keyCode + modifiers rawValue persisted as two scalars).
        let reloaded = SettingsModel(defaults: defaults)
        XCTAssertEqual(reloaded.hotkey, chord)
        XCTAssertEqual(reloaded.hotkey.modifiers, [.command, .shift])
    }

    @MainActor
    func testHistorySizeAndBlocklistPersistAcrossModels() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        do {
            let model = SettingsModel(defaults: defaults)
            model.historySize = 42
            model.addToBlocklist("com.example.secret")
            model.addToBlocklist("org.foo.bar")
            model.addToBlocklist("com.example.secret") // dedup
        }
        let reloaded = SettingsModel(defaults: defaults)
        XCTAssertEqual(reloaded.historySize, 42)
        XCTAssertEqual(reloaded.blocklist, ["com.example.secret", "org.foo.bar"])
    }

    @MainActor
    func testHistorySizeClampsToAtLeastOne() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = SettingsModel(defaults: defaults)
        model.historySize = 0
        XCTAssertEqual(model.historySize, 1, "zero clamps up to the floor of 1")
        model.historySize = -10
        XCTAssertEqual(model.historySize, 1, "negative clamps up to 1")
    }

    @MainActor
    func testStoredZeroHistorySizeFallsBackToDefault() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // Simulate a corrupt/legacy stored 0 → load should fall back to default.
        defaults.set(0, forKey: SettingsModel.Key.clipboardHistorySize)
        let model = SettingsModel(defaults: defaults)
        XCTAssertEqual(model.historySize, SettingsModel.defaultHistorySize)
    }

    @MainActor
    func testBlocklistAddRemoveRoundTrip() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = SettingsModel(defaults: defaults)
        model.addToBlocklist("  com.padded.type  ") // trimmed
        XCTAssertEqual(model.blocklist, ["com.padded.type"])
        model.addToBlocklist("   ") // blank → no-op
        XCTAssertEqual(model.blocklist, ["com.padded.type"])
        model.removeFromBlocklist("com.padded.type")
        XCTAssertEqual(model.blocklist, [])
    }

    // MARK: - SettingsModel change callbacks

    @MainActor
    func testChangeCallbacksFireOnMutation() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = SettingsModel(defaults: defaults)
        var hotkeyFired: HotkeyChord?
        var sizeFired: Int?
        var blocklistFired: Set<String>?
        model.onHotkeyChange = { hotkeyFired = $0 }
        model.onHistorySizeChange = { sizeFired = $0 }
        model.onBlocklistChange = { blocklistFired = $0 }

        let chord = HotkeyChord(keyCode: 1, modifiers: .control) // ⌃S
        model.updateHotkey(chord)
        model.historySize = 99
        model.addToBlocklist("com.x")

        XCTAssertEqual(hotkeyFired, chord)
        XCTAssertEqual(sizeFired, 99)
        XCTAssertEqual(blocklistFired, ["com.x"])
    }

    @MainActor
    func testCallbacksDoNotFireForNoOpAssignments() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = SettingsModel(defaults: defaults)
        var hotkeyCount = 0
        model.onHotkeyChange = { _ in hotkeyCount += 1 }
        // Assigning the identical chord must not notify.
        model.updateHotkey(model.hotkey)
        XCTAssertEqual(hotkeyCount, 0, "setting the same value is a no-op (no callback)")
    }

    // MARK: - InMemoryTokenStore (the TokenStoring fake)

    func testTokenStoreSetGetDelete() {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.token(plugin: "com.vee.github", account: "default"))
        XCTAssertFalse(store.hasToken(plugin: "com.vee.github", account: "default"))

        store.setToken("ghp_secret", plugin: "com.vee.github", account: "default")
        XCTAssertEqual(store.token(plugin: "com.vee.github", account: "default"), "ghp_secret")
        XCTAssertTrue(store.hasToken(plugin: "com.vee.github", account: "default"))

        // Isolation: a different plugin/account does not see it.
        XCTAssertNil(store.token(plugin: "com.vee.linear", account: "default"))
        XCTAssertNil(store.token(plugin: "com.vee.github", account: "other"))

        store.deleteToken(plugin: "com.vee.github", account: "default")
        XCTAssertNil(store.token(plugin: "com.vee.github", account: "default"))
    }

    func testTokenStoreEmptyStringClears() {
        let store = InMemoryTokenStore()
        store.setToken("abc", plugin: "p", account: "a")
        store.setToken("", plugin: "p", account: "a") // empty → clear
        XCTAssertNil(store.token(plugin: "p", account: "a"),
                     "an empty token erases the stored value")
    }
}
