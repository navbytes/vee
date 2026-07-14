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
    /// Opt-in "combine all plugins into one menu bar item" (issue #45 — menu-bar crowding).
    /// Unlike `launchAtLogin` (which needs `LoginItemManager`, a `VeeApp`-layer
    /// type `VeeUI` can't import) this reads/writes `AppPreferences` directly —
    /// `VeeUI` already depends on `VeePreferences` — so no callback plumbing
    /// through `AppController` is needed.
    @Published public var compactMenuBar: Bool

    /// The opt-in "Search All Plugins" global hotkey (cross-plugin search
    /// panel) — off by default, no default combination. Mirrors the per-plugin
    /// hotkey control's shape (`PluginSettingsModel`/`PluginSettingsView.swift`),
    /// just scoped to the app instead of one plugin.
    @Published public var searchAllHotkeyEnabled: Bool
    @Published public var searchAllHotkeyCombo: String
    @Published public var searchAllHotkeyStatus: HotkeyStatus

    public var onLaunchAtLogin: (Bool) -> Void
    public var onChooseFolder: () -> Void
    public var onOpenFolder: () -> Void
    public var onRefreshAll: () -> Void
    public var onCompactMenuBar: (Bool) -> Void
    private let onApplySearchAllHotkey: (Bool, String) -> HotkeyStatus

    public init(
        currentDirectory: String,
        launchAtLogin: Bool,
        onLaunchAtLogin: @escaping (Bool) -> Void,
        onChooseFolder: @escaping () -> Void,
        onOpenFolder: @escaping () -> Void,
        onRefreshAll: @escaping () -> Void,
        compactMenuBar: Bool = AppPreferences.shared.compactMenuBar,
        onCompactMenuBar: @escaping (Bool) -> Void = { AppPreferences.shared.compactMenuBar = $0 },
        searchAllHotkeyEnabled: Bool = AppPreferences.shared.searchAllHotkeyEnabled,
        searchAllHotkeyCombo: String = AppPreferences.shared.searchAllHotkeyCombo ?? "",
        searchAllHotkeyStatus: HotkeyStatus = .none,
        onApplySearchAllHotkey: @escaping (Bool, String) -> HotkeyStatus = { _, _ in .none }
    ) {
        self.currentDirectory = currentDirectory
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
        self.onChooseFolder = onChooseFolder
        self.onOpenFolder = onOpenFolder
        self.onRefreshAll = onRefreshAll
        self.compactMenuBar = compactMenuBar
        self.onCompactMenuBar = onCompactMenuBar
        self.searchAllHotkeyEnabled = searchAllHotkeyEnabled
        self.searchAllHotkeyCombo = searchAllHotkeyCombo
        self.searchAllHotkeyStatus = searchAllHotkeyStatus
        self.onApplySearchAllHotkey = onApplySearchAllHotkey
    }

    /// Applies the current hotkey enable/combo state immediately (a hotkey is a
    /// live system resource, so it commits on change rather than on Save) and
    /// reflects the resulting status — the app-level analog of
    /// `PluginSettingsModel.applyHotkey()`.
    func applySearchAllHotkey() {
        searchAllHotkeyStatus = onApplySearchAllHotkey(searchAllHotkeyEnabled, searchAllHotkeyCombo)
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
                Toggle("Combine all plugins into one menu bar item", isOn: Binding(
                    get: { model.compactMenuBar },
                    set: { model.compactMenuBar = $0; model.onCompactMenuBar($0) }
                ))
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Use this when several plugins are crowding your menu bar. Each plugin's controls move into a submenu of one shared item.")
            }
            Section {
                Toggle(isOn: $model.searchAllHotkeyEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global hotkey")
                            Text("Opens a Spotlight-style panel that fuzzy-searches every enabled plugin's menu at once.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "keyboard")
                    }
                }
                .onChange(of: model.searchAllHotkeyEnabled) { _, _ in model.applySearchAllHotkey() }

                if model.searchAllHotkeyEnabled {
                    TextField("Shortcut", text: $model.searchAllHotkeyCombo, prompt: Text("e.g. cmd+shift+/"))
                        .onSubmit { model.applySearchAllHotkey() }
                    searchAllHotkeyStatusLabel
                }
            } header: {
                Text("Search All Plugins")
            } footer: {
                Text("Off by default — no key combination is claimed until you set one.")
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

    /// Mirrors `PluginSettingsFormContent.hotkeyStatusLabel` (the PR #32
    /// per-plugin status line) so an already-in-use or invalid combination is
    /// surfaced the same way here.
    @ViewBuilder
    private var searchAllHotkeyStatusLabel: some View {
        switch model.searchAllHotkeyStatus {
        case .active(let display):
            Label("Active — \(display)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .unavailable(let display):
            Label("\(display) is already in use — try another", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .invalid:
            Label("Not a valid shortcut", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        case .disabled, .none:
            EmptyView()
        }
    }
}
