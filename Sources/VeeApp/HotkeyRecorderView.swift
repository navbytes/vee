#if canImport(AppKit)
import AppKit
#endif
import Foundation
import VeeServices

// MARK: - Pure NSEvent → HotkeyChord mapping (unit-tested)

/// A value snapshot of the parts of an `NSEvent` the recorder cares about: the
/// virtual key code and the raw modifier-flag bits (as delivered by
/// `NSEvent.modifierFlags.rawValue`). Capturing these as plain integers lets the
/// chord-mapping logic be a PURE function tested with synthetic input — no real
/// `NSEvent` (which can't be hand-constructed) required.
public struct RawKeyEvent: Equatable, Sendable {
    public var keyCode: Int
    /// Raw modifier flags, i.e. `NSEvent.ModifierFlags.rawValue`.
    public var rawModifierFlags: UInt
    public init(keyCode: Int, rawModifierFlags: UInt) {
        self.keyCode = keyCode
        self.rawModifierFlags = rawModifierFlags
    }
}

/// Pure mapping between AppKit key events and `HotkeyChord`. No AppKit types in
/// the signatures (it works on `RawKeyEvent`'s integers), so the whole thing is
/// unit-testable by feeding synthetic keyCode + modifier-flag bits.
public enum HotkeyEventMapper {

    /// AppKit `NSEvent.ModifierFlags` raw bit values (stable Cocoa constants).
    /// Duplicated here as plain integers so the mapper has zero AppKit dependency
    /// and tests can assemble flags without importing AppKit.
    public enum FlagBits {
        public static let command: UInt = 1 << 20   // 1048576
        public static let option: UInt  = 1 << 19   // 524288
        public static let control: UInt = 1 << 18   // 262144
        public static let shift: UInt   = 1 << 17   // 131072
    }

    /// Map raw modifier-flag bits → the chord's `Modifiers` option set, ignoring
    /// any non-modifier bits (caps lock, function, device-dependent bits, etc.).
    public static func modifiers(fromRawFlags raw: UInt) -> HotkeyChord.Modifiers {
        var mods: HotkeyChord.Modifiers = []
        if raw & FlagBits.command != 0 { mods.insert(.command) }
        if raw & FlagBits.option  != 0 { mods.insert(.option) }
        if raw & FlagBits.control != 0 { mods.insert(.control) }
        if raw & FlagBits.shift   != 0 { mods.insert(.shift) }
        return mods
    }

    /// Build a `HotkeyChord` from a raw key event. Returns `nil` for events that
    /// can't form a usable global hotkey:
    ///   • a bare key with NO modifiers (would hijack normal typing), and
    ///   • a modifier-only press (the key code is itself a modifier — there's no
    ///     "real" key yet). Modifier key codes: ⌘ 54/55, ⇧ 56/60, ⌥ 58/61,
    ///     ⌃ 59/62, caps 57, fn 63.
    public static func chord(from event: RawKeyEvent) -> HotkeyChord? {
        guard !modifierKeyCodes.contains(event.keyCode) else { return nil }
        let mods = modifiers(fromRawFlags: event.rawModifierFlags)
        guard !mods.isEmpty else { return nil }
        return HotkeyChord(keyCode: event.keyCode, modifiers: mods)
    }

    /// Virtual key codes that are themselves modifier keys (so a keyDown on one
    /// is not a complete chord).
    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    // MARK: Display

    /// Render a chord as its key-cap glyph sequence, e.g. `⌃⌥⌘Space` —
    /// modifiers in the canonical Cocoa order (⌃⌥⇧⌘) followed by the key glyph.
    public static func displayString(for chord: HotkeyChord) -> String {
        modifierGlyphs(chord.modifiers) + keyGlyph(forKeyCode: chord.keyCode)
    }

    /// The modifier glyphs in canonical menu order (Control, Option, Shift,
    /// Command — matching how macOS renders shortcut equivalents).
    public static func modifierGlyphs(_ mods: HotkeyChord.Modifiers) -> String {
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option)  { out += "⌥" }
        if mods.contains(.shift)   { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        return out
    }

    /// A human-readable glyph/label for a virtual key code. Covers the common
    /// keys a launcher hotkey uses; unknown codes fall back to `key NN`.
    public static func keyGlyph(forKeyCode code: Int) -> String {
        if let named = Self.namedKeys[code] { return named }
        if let letter = Self.letterKeys[code] { return letter }
        if let digit = Self.digitKeys[code] { return digit }
        return "key \(code)"
    }

    private static let namedKeys: [Int: String] = [
        49: "Space", 36: "↩", 76: "⌅", 48: "⇥", 51: "⌫", 117: "⌦",
        53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let letterKeys: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
    ]

    private static let digitKeys: [Int: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]
}

#if canImport(AppKit)

// MARK: - Thin recorder view

/// A thin `NSView` that records the next chord the user presses.
///
/// All decision logic lives in the pure `HotkeyEventMapper`; this view only:
///   • toggles a "recording" state on click / focus,
///   • forwards `keyDown` to the mapper (a complete chord stops recording and
///     fires the callback; a modifier-only press is ignored so the user can hold
///     modifiers before the real key),
///   • renders the current chord as key-caps via `displayString(for:)`.
///
/// Not unit-tested (needs a window/first-responder); verified manually. The
/// mapping it relies on IS tested through `HotkeyEventMapper`.
@MainActor
public final class HotkeyRecorderView: NSView {

    /// Called with the newly-recorded chord. The owner persists it (e.g. into
    /// `SettingsModel.hotkey`).
    public var onChordRecorded: ((HotkeyChord) -> Void)?

    /// The chord currently displayed (the recorder shows this when idle).
    public var chord: HotkeyChord? {
        didSet { updateTitle() }
    }

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false { didSet { updateTitle(); needsDisplay = true } }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        updateTitle()
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var wantsUpdateLayer: Bool { true }

    public override func updateLayer() {
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.quaternaryLabelColor).cgColor
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { beginRecording() }
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    private func beginRecording() { isRecording = true }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        // Escape cancels recording without changing the chord.
        if event.keyCode == 53 { isRecording = false; return }
        let raw = RawKeyEvent(keyCode: Int(event.keyCode),
                              rawModifierFlags: event.modifierFlags.rawValue)
        if let captured = HotkeyEventMapper.chord(from: raw) {
            chord = captured
            isRecording = false
            onChordRecorded?(captured)
        }
        // Otherwise (bare key or modifier-only) keep waiting for a full chord.
    }

    private func updateTitle() {
        if isRecording {
            label.stringValue = "Type a shortcut…"
            label.textColor = .secondaryLabelColor
        } else if let chord {
            label.stringValue = HotkeyEventMapper.displayString(for: chord)
            label.textColor = .labelColor
        } else {
            label.stringValue = "Click to record"
            label.textColor = .tertiaryLabelColor
        }
    }
}

#endif
