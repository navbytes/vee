import Foundation

/// Which presentation a plugin's global hotkey (`<vee.shortcut>`) opens.
///
/// Vee has one menu surface with two presentations: the transient search panel
/// that dismisses on the next click, and a detached window that can be left on
/// the desktop. They render the same content through the same view, so this is
/// a choice of lifetime and chrome — not a choice between two different
/// features, and not something the user gives anything up by making. The window
/// carries the panel's search field too.
///
/// There is deliberately no second `<vee.*>` declaration for this. A plugin
/// declares one hotkey; what it opens is the user's call, the same way turning
/// it off or rebinding it already is.
public enum HotkeyPresentation: String, Equatable, Sendable, CaseIterable {
    /// The transient panel — the behavior every plugin had before this choice
    /// existed, and the default, so a declared hotkey keeps doing what it did.
    case panel
    /// The detached window. Pressing the hotkey when the window is already open
    /// focuses it rather than opening a second, which makes the hotkey a
    /// per-plugin way back to a window that has been covered up.
    case window

    public static let `default`: HotkeyPresentation = .panel

    /// Resolves a stored preference string, falling back to the default for an
    /// absent or unrecognised value rather than failing — a preference read must
    /// never be able to leave a plugin with no working hotkey.
    public static func resolve(_ stored: String?) -> HotkeyPresentation {
        stored.flatMap(HotkeyPresentation.init(rawValue:)) ?? .default
    }
}
