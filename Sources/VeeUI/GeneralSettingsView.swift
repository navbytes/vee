import SwiftUI
import VeePluginFormat
import VeePreferences

/// Backing model for the Preferences window's **General** tab. It carries the
/// same app-level settings the Plugin Manager exposes (plugins folder,
/// launch-at-login, refresh-all) and forwards edits to the app via callbacks, so
/// the two surfaces share one implementation.
@MainActor
public final class GeneralSettingsModel: ObservableObject {
    @Published public var currentDirectory: String
    @Published public var launchAtLogin: Bool
    /// The app-wide *default* placement, as the toggle's boolean: on means a
    /// plugin with no placement of its own folds into Vee's item, off means it
    /// gets its own (issue #45 — menu-bar crowding). A plugin the user has
    /// placed by hand in the Plugin Manager keeps that placement either way —
    /// see `AppPreferences.setPlacement`.
    ///
    /// Unlike `launchAtLogin` (which needs `LoginItemManager`, a `VeeApp`-layer
    /// type `VeeUI` can't import) this reads/writes `AppPreferences` directly —
    /// `VeeUI` already depends on `VeePreferences` — so no callback plumbing
    /// through `AppController` is needed.
    @Published public var foldPluginsByDefault: Bool
    /// The app-level combination that brings every open plugin window to the
    /// front (empty = unbound), and what binding it actually did. Unlike
    /// `foldPluginsByDefault` this cannot be written straight to `AppPreferences`:
    /// claiming a system-wide combination is `VeeApp`'s job, so the app passes
    /// a closure in and the honest status comes back out.
    @Published public var focusWindowsHotkey: String
    @Published public var focusWindowsHotkeyStatus: HotkeyStatus

    public var onLaunchAtLogin: (Bool) -> Void
    public var onChooseFolder: () -> Void
    public var onOpenFolder: () -> Void
    public var onRefreshAll: () -> Void
    public var onFoldPluginsByDefault: (Bool) -> Void

    private let onApplyFocusWindowsHotkey: (String) -> HotkeyStatus

    public init(
        currentDirectory: String,
        launchAtLogin: Bool,
        onLaunchAtLogin: @escaping (Bool) -> Void,
        onChooseFolder: @escaping () -> Void,
        onOpenFolder: @escaping () -> Void,
        onRefreshAll: @escaping () -> Void,
        foldPluginsByDefault: Bool = AppPreferences.shared.defaultPlacement != .own,
        onFoldPluginsByDefault: @escaping (Bool) -> Void = { AppPreferences.shared.defaultPlacement = $0 ? .foldedDefault : .own },
        focusWindowsHotkey: String = "",
        focusWindowsHotkeyStatus: HotkeyStatus = .none,
        onApplyFocusWindowsHotkey: @escaping (String) -> HotkeyStatus = { _ in .none },
    ) {
        self.currentDirectory = currentDirectory
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
        self.onChooseFolder = onChooseFolder
        self.onOpenFolder = onOpenFolder
        self.onRefreshAll = onRefreshAll
        self.foldPluginsByDefault = foldPluginsByDefault
        self.onFoldPluginsByDefault = onFoldPluginsByDefault
        self.focusWindowsHotkey = focusWindowsHotkey
        self.focusWindowsHotkeyStatus = focusWindowsHotkeyStatus
        self.onApplyFocusWindowsHotkey = onApplyFocusWindowsHotkey
    }

    /// Applies the current hotkey combination immediately (a hotkey is a
    /// live system resource, so it commits on change rather than on Save) and
    /// reflects the resulting status — the app-level analog of
    /// `PluginSettingsModel.applyHotkey()`.
    func applyFocusWindowsHotkey() {
        focusWindowsHotkeyStatus = onApplyFocusWindowsHotkey(focusWindowsHotkey)
    }
}

/// The shared app-level General settings rows (plugins folder chooser +
/// launch-at-login). Emits a `Section`, so callers embed it in their own `Form`.
/// Used by both the Preferences window's General tab and the Plugin Manager so
/// the controls are defined once.
public struct GeneralSettingsContent: View {
    private let directory: String
    @Binding private var launchAtLogin: Bool
    private let onChooseFolder: () -> Void

    public init(directory: String, launchAtLogin: Binding<Bool>, onChooseFolder: @escaping () -> Void) {
        self.directory = directory
        self._launchAtLogin = launchAtLogin
        self.onChooseFolder = onChooseFolder
    }

    public var body: some View {
        Section("General") {
            LabeledContent("Plugins folder") {
                HStack(spacing: 8) {
                    Text((directory as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { onChooseFolder() }
                }
            }
            Toggle("Launch Vee at login", isOn: $launchAtLogin)
        }
    }
}

/// The **General** tab: the shared settings rows plus app-wide actions.
public struct GeneralSettingsTab: View {
    @ObservedObject private var model: GeneralSettingsModel
    @FocusState private var hotkeyFieldFocused: Bool

    public init(model: GeneralSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            GeneralSettingsContent(
                directory: model.currentDirectory,
                launchAtLogin: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0; model.onLaunchAtLogin($0) }
                ),
                onChooseFolder: { model.onChooseFolder() }
            )
            Section {
                Toggle("Combine plugins into one menu bar item", isOn: Binding(
                    get: { model.foldPluginsByDefault },
                    set: { model.foldPluginsByDefault = $0; model.onFoldPluginsByDefault($0) }
                ))
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Use this when several plugins are crowding your menu bar. Each plugin's controls move into a submenu of one shared item. This is the default for new plugins — give any single plugin its own item, or hide it from the menu bar entirely, in the Plugin Manager.")
            }
            Section {
                TextField("Bring windows to front", text: $model.focusWindowsHotkey, prompt: Text("e.g. cmd+shift+w"))
                    .focused($hotkeyFieldFocused)
                    // Committed on Return *and* on leaving the field: a hotkey is
                    // a live system resource, and this surface has no Save button
                    // to catch a combination typed and then clicked away from.
                    .onSubmit { model.applyFocusWindowsHotkey() }
                    .onChange(of: hotkeyFieldFocused) { _, focused in
                        if !focused { model.applyFocusWindowsHotkey() }
                    }
                HotkeyStatusLabel(status: model.focusWindowsHotkeyStatus)
            } header: {
                Text("Windows")
            } footer: {
                Text("Brings every open plugin window in front of whatever you are working in. Vee has no Dock icon, so this is the fastest way back to a window you have unpinned and covered. A combination applies when you press Return or leave the field; leave it empty for no shortcut.")
            }
            Section {
                Button {
                    model.onRefreshAll()
                } label: {
                    Label("Refresh All Plugins", systemImage: "arrow.clockwise")
                }
                Button {
                    model.onOpenFolder()
                } label: {
                    Label("Open Plugins Folder", systemImage: "folder")
                }
            }
        }
        .formStyle(.grouped)
    }

}
