import SwiftUI
import VeePluginFormat
import VeePreferences
import VeeTrust

/// One row in the plugin manager.
public struct PluginManagerRow: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var interval: String
    /// The human-readable trust summary shown beside the shield.
    public var trust: String
    /// What the shield actually means. Carried as the parsed level rather than
    /// re-derived from `trust`: the shield used to pick its colour by
    /// substring-matching that prose ("declared" and not "un"), so rewording a
    /// user-facing string — or translating it — would silently turn an
    /// undeclared plugin's shield green.
    public var trustLevel: TrustLevel
    public var isEnabled: Bool
    public var hasSettings: Bool
    /// The plugin's effective Vee-native features (search panel, active hotkey),
    /// shown as small indicators.
    public var features: PluginFeatures
    /// The last run's error message, if it failed. Surfaced as a badge that
    /// opens the debug console; `nil` when the plugin is healthy or disabled.
    public var lastError: String?
    /// The plugin's output surface (`<vee.surface>`). Shown as a badge so a
    /// widget-only plugin — which has no menu-bar item — is still visible and
    /// identifiable in the Manager.
    public var surface: HeaderMetadata.WidgetSurface
    /// Where the user has placed this plugin in the menu bar, or `nil` when it
    /// follows the app-wide default. The *override* rather than the resolved
    /// placement, so the row can offer "Use Default" honestly and so a plugin
    /// following the default moves with it.
    public var placement: BarPlacement?

    public init(id: String, name: String, interval: String, trust: String, trustLevel: TrustLevel = .undeclared, isEnabled: Bool, hasSettings: Bool, features: PluginFeatures = PluginFeatures(), lastError: String? = nil, surface: HeaderMetadata.WidgetSurface = .menu, placement: BarPlacement? = nil) {
        self.id = id
        self.name = name
        self.interval = interval
        self.trust = trust
        self.trustLevel = trustLevel
        self.isEnabled = isEnabled
        self.hasSettings = hasSettings
        self.features = features
        self.lastError = lastError
        self.surface = surface
        self.placement = placement
    }
}

/// Model backing the plugin manager window. The app supplies the rows and the
/// action callbacks.
@MainActor
public final class PluginManagerModel: ObservableObject {
    @Published public var rows: [PluginManagerRow]
    /// Whether the rows have finished loading. Built off the main thread, so the
    /// window shows a brief loader instead of flashing the "no plugins" empty
    /// state before the rows arrive. Set `true` by the app once `rows` is populated.
    @Published public var isLoaded: Bool = false
    @Published public var currentDirectory: String
    @Published public var launchAtLogin: Bool
    /// The app-wide default placement, so a row following it can name what
    /// "Use Default" actually means rather than saying it abstractly.
    @Published public var defaultPlacement: BarPlacement

    public var onToggleEnabled: (String, Bool) -> Void
    public var onReveal: (String) -> Void
    public var onSettings: (String) -> Void
    public var onDebug: (String) -> Void
    /// Re-runs one plugin. Reachable here because a plugin hidden from the menu
    /// bar has no dropdown of its own to offer it.
    public var onRefresh: (String) -> Void
    /// Opens one plugin's detached window — the same reason as `onRefresh`, and
    /// the guarantee `detached-plugin-windows` makes for *every* plugin.
    public var onOpenWindow: (String) -> Void
    /// Places one plugin in the menu bar, or with `nil` returns it to the
    /// app-wide default.
    public var onSetPlacement: (String, BarPlacement?) -> Void
    public var onDelete: (String) -> Void
    public var onDiscover: () -> Void
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
        onRefresh: @escaping (String) -> Void = { _ in },
        onOpenWindow: @escaping (String) -> Void = { _ in },
        defaultPlacement: BarPlacement = .own,
        onSetPlacement: @escaping (String, BarPlacement?) -> Void = { _, _ in },
        onDelete: @escaping (String) -> Void = { _ in },
        onDiscover: @escaping () -> Void = {},
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
        self.onRefresh = onRefresh
        self.onOpenWindow = onOpenWindow
        self.defaultPlacement = defaultPlacement
        self.onSetPlacement = onSetPlacement
        self.onDelete = onDelete
        self.onDiscover = onDiscover
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

    /// Updates one row's last-run error live while the window is open. Only
    /// mutates when the value actually changed, so a healthy plugin publishing
    /// its title on every tick doesn't churn the view.
    public func setError(_ error: String?, id: String) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), rows[idx].lastError != error else { return }
        rows[idx].lastError = error
    }

    /// Places one plugin, reflecting it in the row immediately for responsive
    /// feedback before telling the app — the same shape `delete(_:)` uses.
    func setPlacement(_ placement: BarPlacement?, id: String) {
        if let idx = rows.firstIndex(where: { $0.id == id }) {
            rows[idx].placement = placement
        }
        onSetPlacement(id, placement)
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
                if !model.isLoaded {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                } else if model.rows.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No plugins yet", systemImage: "puzzlepiece.extension")
                        } description: {
                            Text("Add scripts to your plugins folder, or install one from Discover.")
                        } actions: {
                            Button {
                                model.onDiscover()
                            } label: {
                                Label("Browse Discover", systemImage: "square.grid.2x2")
                            }
                            .buttonStyle(.borderedProminent)
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
/// appears on hover, and a trailing enable toggle. Internal (not `private`) so
/// the consolidated `LibraryView` reuses it for its Installed section.
struct ManagerRow: View {
    @ObservedObject var model: PluginManagerModel
    let row: PluginManagerRow
    /// When `true` (the consolidated window's Installed list), the identity area
    /// (icon + name + metadata) is a `NavigationLink` to the plugin's in-pane
    /// Settings/Debug detail. The trailing overflow menu and enable toggle stay
    /// *outside* the link as independent controls, so tapping them never
    /// navigates. The standalone Plugin Manager window passes `false` (default),
    /// leaving the row a plain, non-navigating row exactly as before.
    var navigatesToDetail: Bool = false
    @State private var hovering = false
    @State private var confirmingDelete = false

    /// Where this plugin sits in the menu bar. The checkmark tracks the row's
    /// *override* rather than its resolved placement, so "Use Default" reads
    /// honestly: a plugin that follows the default is checked there, and moves
    /// when the default moves.
    private var placementMenu: some View {
        Menu {
            placementRow("Its Own Menu Bar Item", BarPlacement.own)
            placementRow("Combined Under Vee", BarPlacement.foldedDefault)
            placementRow("Hidden From Menu Bar", BarPlacement.hidden)
            Divider()
            placementRow(defaultPlacementLabel, nil)
        } label: {
            Label("Menu Bar", systemImage: placementSymbol)
        }
    }

    private func placementRow(_ title: String, _ placement: BarPlacement?) -> some View {
        let isCurrent = row.placement == placement
        return Button {
            model.setPlacement(placement, id: row.id)
        } label: {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var defaultPlacementLabel: String {
        switch model.defaultPlacement {
        case .own: "Use Default (Its Own Item)"
        case .folded: "Use Default (Combined)"
        case .hidden: "Use Default (Hidden)"
        }
    }

    private var placementSymbol: String {
        switch row.placement ?? model.defaultPlacement {
        case .own: "menubar.rectangle"
        case .folded: "rectangle.stack"
        case .hidden: "eye.slash"
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            if navigatesToDetail {
                NavigationLink(value: row.id) { identity }
                    .buttonStyle(.plain)
            } else {
                identity
            }

            Menu {
                // Every per-plugin action lives here, not only the ones the
                // dropdown lacks: a plugin hidden from the menu bar has no
                // dropdown at all, and this row is its route to all of them.
                Button { model.onRefresh(row.id) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { model.onOpenWindow(row.id) } label: { Label("Open in Window", systemImage: "macwindow") }
                if row.hasSettings {
                    Button { model.onSettings(row.id) } label: { Label("Settings…", systemImage: "slider.horizontal.3") }
                }
                Button { model.onDebug(row.id) } label: { Label("Debug…", systemImage: "ladybug") }
                Button { model.onReveal(row.id) } label: { Label("Reveal in Finder", systemImage: "folder") }
                // A widget-only plugin has no menu-bar presence to place — its
                // author declared it away, and that is not the user's to
                // override here (see `BarPlacement`).
                if row.surface != .widget {
                    Divider()
                    placementMenu
                }
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
            // Only the script is recoverable. Disk reconciliation
            // (`AppController.reconcileDiskState`) fires on the very next
            // reload and permanently removes this plugin's settings, its
            // saved passwords and tokens from the Keychain, and its install
            // record — so restoring the file from the Trash brings back a
            // plugin that has to be set up again from scratch. Promising a
            // clean restore was the part of this dialog that wasn't true.
            Text("The plugin script will be moved to the Trash. Its settings, saved passwords and install history are deleted and cannot be restored.")
        }
    }

    /// The row's identity: icon, name, and metadata badges. Rendered plainly in
    /// the standalone window, or wrapped in a `NavigationLink` in the Installed
    /// list (see `navigatesToDetail`). `.contentShape` makes the whole area —
    /// including gaps between badges — a single tap target for the link.
    private var identity: some View {
        HStack(spacing: 11) {
            PluginTile(symbol: "puzzlepiece.extension.fill", tint: row.isEnabled ? .accentColor : .secondary, size: 30)
                .opacity(row.isEnabled ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).fontWeight(.medium)
                // Badge doctrine (see DesignKit): filled `TrustChip` is reserved
                // for state that matters (trust, error); descriptive metadata
                // (schedule, surface, hotkey) is a muted `MetaChip` so it doesn't
                // compete. Trust and error lead; metadata trails.
                HStack(spacing: Space.sm) {
                    if !row.trust.isEmpty {
                        TrustChip(symbol: trustSymbol, label: row.trust, tint: trustTint)
                    }
                    if let error = row.lastError {
                        Button { model.onDebug(row.id) } label: {
                            TrustChip(symbol: "exclamationmark.triangle.fill", label: "Error", tint: .red)
                        }
                        .buttonStyle(.plain)
                        .help(error)
                        .accessibilityLabel("Last run failed: \(error). Open debug console.")
                    }
                    if !row.interval.isEmpty {
                        MetaChip(symbol: "clock", label: row.interval)
                    }
                    if row.surface != .menu {
                        MetaChip(
                            symbol: row.surface == .widget ? "square.grid.2x2.fill" : "square.grid.2x2",
                            label: row.surface == .widget ? "Widget-only" : "Widget",
                            tint: .purple
                        )
                        .help(row.surface == .widget
                              ? "Widget-only — no menu-bar item; add it in Notification Center"
                              : "Shows in the menu bar and as a widget")
                    }
                    if row.features.searchPanel {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Searchable menu (⌘F)")
                            .accessibilityLabel("Searchable menu")
                    }
                    if let hotkey = row.features.hotkey {
                        MetaChip(symbol: "keyboard", label: hotkey)
                            .help("Global hotkey")
                            .accessibilityLabel("Global hotkey \(hotkey)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var trustTint: Color {
        switch row.trustLevel {
        case .declared: return .green
        case .partial: return .orange
        case .undeclared: return .secondary
        }
    }
    private var trustSymbol: String {
        switch row.trustLevel {
        case .declared: return "checkmark.shield.fill"
        case .partial: return "exclamationmark.shield.fill"
        case .undeclared: return "shield"
        }
    }
}
