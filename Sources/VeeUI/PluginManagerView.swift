import SwiftUI

/// One row in the plugin manager.
public struct PluginManagerRow: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var interval: String
    public var trust: String
    public var isEnabled: Bool
    public var hasSettings: Bool

    public init(id: String, name: String, interval: String, trust: String, isEnabled: Bool, hasSettings: Bool) {
        self.id = id
        self.name = name
        self.interval = interval
        self.trust = trust
        self.isEnabled = isEnabled
        self.hasSettings = hasSettings
    }
}

/// Model backing the plugin manager window. The app supplies the rows and the
/// action callbacks.
@MainActor
public final class PluginManagerModel: ObservableObject {
    @Published public var rows: [PluginManagerRow]
    @Published public var currentDirectory: String
    @Published public var launchAtLogin: Bool

    public var onToggleEnabled: (String, Bool) -> Void
    public var onReveal: (String) -> Void
    public var onSettings: (String) -> Void
    public var onLaunchAtLogin: (Bool) -> Void
    public var onOpenFolder: () -> Void
    public var onChooseFolder: () -> Void
    public var onRefreshAll: () -> Void

    public init(
        rows: [PluginManagerRow],
        currentDirectory: String,
        launchAtLogin: Bool,
        onToggleEnabled: @escaping (String, Bool) -> Void,
        onReveal: @escaping (String) -> Void,
        onSettings: @escaping (String) -> Void,
        onLaunchAtLogin: @escaping (Bool) -> Void,
        onOpenFolder: @escaping () -> Void,
        onChooseFolder: @escaping () -> Void,
        onRefreshAll: @escaping () -> Void
    ) {
        self.rows = rows
        self.currentDirectory = currentDirectory
        self.launchAtLogin = launchAtLogin
        self.onToggleEnabled = onToggleEnabled
        self.onReveal = onReveal
        self.onSettings = onSettings
        self.onLaunchAtLogin = onLaunchAtLogin
        self.onOpenFolder = onOpenFolder
        self.onChooseFolder = onChooseFolder
        self.onRefreshAll = onRefreshAll
    }

    func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.rows.first { $0.id == id }?.isEnabled ?? false },
            set: { newValue in
                if let idx = self.rows.firstIndex(where: { $0.id == id }) {
                    self.rows[idx].isEnabled = newValue
                }
                self.onToggleEnabled(id, newValue)
            }
        )
    }
}

/// Lists all discovered plugins with enable/disable, trust, and quick actions.
public struct PluginManagerView: View {
    @ObservedObject private var model: PluginManagerModel

    public init(model: PluginManagerModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plugins").font(.headline)
                Spacer()
                Button("Refresh All") { model.onRefreshAll() }
                Button("Open Folder…") { model.onOpenFolder() }
            }

            if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Text("No plugins found").font(.title3)
                    Text("Add executable plugins to your plugins folder.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            Toggle("", isOn: model.enabledBinding(row.id)).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).fontWeight(.medium)
                                Text("\(row.interval)\(row.trust.isEmpty ? "" : " · \(row.trust)")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if row.hasSettings {
                                Button("Settings…") { model.onSettings(row.id) }
                            }
                            Button("Reveal") { model.onReveal(row.id) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 220)
            }

            Divider()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plugins folder").font(.caption).foregroundStyle(.secondary)
                    Text((model.currentDirectory as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Choose…") { model.onChooseFolder() }
            }

            Toggle("Launch Vee at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0; model.onLaunchAtLogin($0) }
            ))
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
