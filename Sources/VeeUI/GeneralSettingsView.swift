import SwiftUI

/// Backing model for the Preferences window's **General** tab. It carries the
/// same app-level settings the Plugin Manager exposes (plugins folder,
/// launch-at-login, refresh-all) and forwards edits to the app via callbacks, so
/// the two surfaces share one implementation.
@MainActor
public final class GeneralSettingsModel: ObservableObject {
    @Published public var currentDirectory: String
    @Published public var launchAtLogin: Bool

    public var onLaunchAtLogin: (Bool) -> Void
    public var onChooseFolder: () -> Void
    public var onOpenFolder: () -> Void
    public var onRefreshAll: () -> Void

    public init(
        currentDirectory: String,
        launchAtLogin: Bool,
        onLaunchAtLogin: @escaping (Bool) -> Void,
        onChooseFolder: @escaping () -> Void,
        onOpenFolder: @escaping () -> Void,
        onRefreshAll: @escaping () -> Void
    ) {
        self.currentDirectory = currentDirectory
        self.launchAtLogin = launchAtLogin
        self.onLaunchAtLogin = onLaunchAtLogin
        self.onChooseFolder = onChooseFolder
        self.onOpenFolder = onOpenFolder
        self.onRefreshAll = onRefreshAll
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
