import Foundation
import VeeApp
import VeeServices

/// Wires a `SettingsModel`'s change callbacks to the live app services and owns
/// the small amount of state that bridging needs (the last-applied blocklist, so
/// edits can be diffed into the monitor's add/remove API).
///
/// Pulled into its own `@MainActor` type so `main.swift`'s bootstrap closure
/// stays small and the binding's state has a clear owner (rather than a captured
/// mutable local). The model's callbacks fire on the main thread.
@MainActor
final class SettingsBinder {
    private let model: SettingsModel
    private let clipboard: ClipboardMonitor
    /// Re-bind the launcher hotkey to a new chord (provided by the app, which
    /// owns the `HotkeyDispatcher`).
    private let rebindHotkey: (HotkeyChord) -> Void
    /// Blocklist currently applied to the monitor, for diffing live edits.
    private var appliedBlocklist: Set<String>

    init(model: SettingsModel,
         clipboard: ClipboardMonitor,
         rebindHotkey: @escaping (HotkeyChord) -> Void) {
        self.model = model
        self.clipboard = clipboard
        self.rebindHotkey = rebindHotkey
        self.appliedBlocklist = model.blocklist
    }

    /// Install the change callbacks. Call once after the initial state has been
    /// applied (hotkey bound, blocklist seeded).
    func activate() {
        model.onHotkeyChange = { [weak self] chord in
            self?.rebindHotkey(chord)
        }
        model.onBlocklistChange = { [weak self] newList in
            guard let self else { return }
            for added in newList.subtracting(self.appliedBlocklist) {
                self.clipboard.addToBlocklist(added)
            }
            for removed in self.appliedBlocklist.subtracting(newList) {
                self.clipboard.removeFromBlocklist(removed)
            }
            self.appliedBlocklist = newList
        }
        // NOTE: clipboard history *size* is fixed at monitor construction
        // (`historyLimit` is immutable post-init); a live size change therefore
        // takes effect on the next launch. The initial saved size is applied when
        // the monitor is constructed.
    }
}
