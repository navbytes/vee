import SwiftUI
import VeePluginFormat

/// One row in the plugin manager.
public struct PluginManagerRow: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var interval: String
    public var trust: String
    public var isEnabled: Bool
    public var hasSettings: Bool
    /// The plugin's effective Vee-native features (search panel, active hotkey),
    /// shown as small indicators.
    public var features: PluginFeatures
    /// The last run's error message, if it failed. Surfaced as a badge that
    /// opens the debug console; `nil` when the plugin is healthy or disabled.
    public var lastError: String?

    public init(id: String, name: String, interval: String, trust: String, isEnabled: Bool, hasSettings: Bool, features: PluginFeatures = PluginFeatures(), lastError: String? = nil) {
        self.id = id
        self.name = name
        self.interval = interval
        self.trust = trust
        self.isEnabled = isEnabled
        self.hasSettings = hasSettings
        self.features = features
        self.lastError = lastError
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
    public var onDebug: (String) -> Void
    public var onDelete: (String) -> Void
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
        onDebug: @escaping (String) -> Void = { _ in },
        onDelete: @escaping (String) -> Void = { _ in },
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
        self.onDebug = onDebug
        self.onDelete = onDelete
        self.onLaunchAtLogin = onLaunchAtLogin
        self.onOpenFolder = onOpenFolder
        self.onChooseFolder = onChooseFolder
        self.onRefreshAll = onRefreshAll
    }

    /// Removes the row from the list immediately for responsive feedback, then
    /// asks the app to move the plugin file to the Trash.
    func delete(_ id: String) {
        rows.removeAll { $0.id == id }
        onDelete(id)
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
        NavigationStack {
            Form {
                if model.rows.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No plugins yet", systemImage: "puzzlepiece.extension")
                        } description: {
                            Text("Add scripts to your plugins folder, or install one from Discover.")
                        }
                    }
                } else {
                    Section("Plugins") {
                        ForEach(model.rows) { row in
                            ManagerRow(model: model, row: row)
                        }
                    }
                }

                GeneralSettingsContent(
                    directory: model.currentDirectory,
                    launchAtLogin: Binding(
                        get: { model.launchAtLogin },
                        set: { model.launchAtLogin = $0; model.onLaunchAtLogin($0) }
                    ),
                    onChooseFolder: { model.onChooseFolder() }
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Plugins")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.onRefreshAll()
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh all plugins")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.onOpenFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                    .help("Open the plugins folder in Finder")
                }
            }
        }
        .frame(minWidth: 500, minHeight: 460)
    }
}

/// A single plugin row: icon, name, schedule + trust, an overflow menu that
/// appears on hover, and a trailing enable toggle.
private struct ManagerRow: View {
    @ObservedObject var model: PluginManagerModel
    let row: PluginManagerRow
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 11) {
            PluginTile(symbol: "puzzlepiece.extension.fill", tint: row.isEnabled ? .accentColor : .secondary, size: 30)
                .opacity(row.isEnabled ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).fontWeight(.medium)
                HStack(spacing: 6) {
                    if !row.interval.isEmpty {
                        Label(row.interval, systemImage: "clock").labelStyle(.titleAndIcon)
                    }
                    if !row.trust.isEmpty {
                        TrustChip(symbol: trustSymbol, label: row.trust, tint: trustTint)
                    }
                    if row.features.searchPanel {
                        Image(systemName: "magnifyingglass")
                            .help("Searchable menu (⌘F)")
                            .accessibilityLabel("Searchable menu")
                    }
                    if let hotkey = row.features.hotkey {
                        Label(hotkey, systemImage: "keyboard")
                            .labelStyle(.titleAndIcon)
                            .help("Global hotkey")
                            .accessibilityLabel("Global hotkey \(hotkey)")
                    }
                    if let error = row.lastError {
                        Button { model.onDebug(row.id) } label: {
                            TrustChip(symbol: "exclamationmark.triangle.fill", label: "Error", tint: .red)
                        }
                        .buttonStyle(.plain)
                        .help(error)
                        .accessibilityLabel("Last run failed: \(error). Open debug console.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Menu {
                if row.hasSettings {
                    Button { model.onSettings(row.id) } label: { Label("Settings…", systemImage: "slider.horizontal.3") }
                }
                Button { model.onDebug(row.id) } label: { Label("Debug…", systemImage: "ladybug") }
                Button { model.onReveal(row.id) } label: { Label("Reveal in Finder", systemImage: "folder") }
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            // Kept faint until hover for a calm resting state, but always fully
            // opaque under VoiceOver / keyboard focus so it isn't easy to miss.
            .opacity(hovering ? 1 : 0.35)
            .accessibilityLabel("Actions for \(row.name)")

            Toggle("", isOn: model.enabledBinding(row.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(row.name)")
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
        .confirmationDialog("Delete “\(row.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.delete(row.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plugin script will be moved to the Trash. You can restore it from there.")
        }
    }

    private var trustTint: Color {
        let t = row.trust.lowercased()
        if t.contains("declared") && !t.contains("un") { return .green }
        if t.contains("incomplete") || t.contains("partial") { return .orange }
        return .secondary
    }
    private var trustSymbol: String {
        let t = row.trust.lowercased()
        if t.contains("declared") && !t.contains("un") { return "checkmark.shield.fill" }
        if t.contains("incomplete") || t.contains("partial") { return "exclamationmark.shield.fill" }
        return "shield"
    }
}
