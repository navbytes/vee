import SwiftUI

/// The sections of the consolidated Vee window (see
/// `docs/design/ui-consolidation.md`). One window, sidebar-navigated, instead of
/// separate Preferences / Plugin Manager / Discover windows.
public enum LibrarySection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case installed
    case discover
    case variables
    case stores
    case general

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .installed: return "Installed"
        case .discover: return "Discover"
        case .variables: return "Variables"
        case .stores: return "Stores"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .installed: return "square.grid.2x2"
        case .discover: return "sparkle.magnifyingglass"
        case .variables: return "curlybraces"
        case .stores: return "shippingbox"
        case .general: return "gearshape"
        }
    }
}

/// Backs the consolidated window, holding the sub-models for each section. The
/// installed rows are built off the main thread (see `AppController`); the other
/// sub-models are cheap. The Discover catalog browser is embedded directly (the
/// `browser` model, whose catalog is retained across opens by `AppController`),
/// so there's no standalone-window callback anymore.
@MainActor
public final class LibraryModel: ObservableObject {
    @Published public var section: LibrarySection
    public let manager: PluginManagerModel
    public let general: GeneralSettingsModel
    public let stores: StoresSettingsModel
    public let variables: VariablesEditorModel
    public let browser: PluginBrowserModel
    /// Resolves an installed plugin's id to its live Settings/Debug models so the
    /// Installed section can show them in-pane. Returns `nil` for an unknown id
    /// (e.g. a plugin removed while the window is open). Supplied by the app,
    /// which owns the per-plugin coordinators.
    public let pluginDetail: (String) -> PluginDetailModels?

    public init(
        section: LibrarySection = .installed,
        manager: PluginManagerModel,
        general: GeneralSettingsModel,
        stores: StoresSettingsModel,
        variables: VariablesEditorModel,
        browser: PluginBrowserModel,
        pluginDetail: @escaping (String) -> PluginDetailModels? = { _ in nil }
    ) {
        self.section = section
        self.manager = manager
        self.general = general
        self.stores = stores
        self.variables = variables
        self.browser = browser
        self.pluginDetail = pluginDetail
    }
}

/// The consolidated window: a sidebar of sections with the matching detail. Each
/// detail reuses the existing views (`GeneralSettingsTab`, `StoresSettingsTab`,
/// `VariablesEditorView`, and the installed-plugins list), so this is
/// composition, not a rewrite.
public struct LibraryView: View {
    @ObservedObject private var model: LibraryModel

    public init(model: LibraryModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Library") {
                    // A live count of installed plugins, the native sidebar idiom
                    // (Mail/Notes). Observes the manager model so it fills in when
                    // the off-main row build finishes.
                    InstalledSidebarLabel(manager: model.manager)
                        .tag(LibrarySection.installed)
                    sidebarRow(.discover)
                }
                Section("Settings") {
                    sidebarRow(.variables)
                    sidebarRow(.stores)
                    sidebarRow(.general)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .frame(minWidth: 800, minHeight: 540)
    }

    private func sidebarRow(_ section: LibrarySection) -> some View {
        Label(section.label, systemImage: section.symbol).tag(section)
    }

    /// The sidebar always has exactly one section selected; a nil from the List
    /// (e.g. a click on empty space) leaves the current one in place.
    private var selection: Binding<LibrarySection?> {
        Binding(get: { model.section }, set: { model.section = $0 ?? model.section })
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .installed:
            InstalledPluginsList(model: model.manager, pluginDetail: model.pluginDetail)
        case .discover:
            DiscoverContentView(model: model.browser)
        case .variables:
            VariablesEditorView(model: model.variables)
        case .stores:
            StoresSettingsTab(model: model.stores)
        case .general:
            GeneralSettingsTab(model: model.general)
        }
    }
}

/// The **Installed** sidebar row, carrying a live plugin count as a native
/// `.badge`. Split into its own view so it observes the manager model directly —
/// `LibraryView` observes only `LibraryModel`, so without this the count would
/// not refresh when the off-main row build populates `rows`. The badge is hidden
/// until the rows load (and when there are none) by passing a count of `0`, which
/// SwiftUI renders as no badge.
private struct InstalledSidebarLabel: View {
    @ObservedObject var manager: PluginManagerModel

    var body: some View {
        Label(LibrarySection.installed.label, systemImage: LibrarySection.installed.symbol)
            .badge(manager.isLoaded ? manager.rows.count : 0)
    }
}

/// A single placeholder row shown while the installed list loads — neutral bars
/// in the row's real shape (tile + two text lines), so the list settles into
/// place instead of popping in from a lone centered spinner.
private struct SkeletonPluginRow: View {
    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.hairline)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Palette.hairline).frame(width: 150, height: 10)
                Capsule().fill(Palette.hairline).frame(width: 96, height: 8)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }
}

/// The Installed section: the plugin list extracted from `PluginManagerView`
/// (minus the folder/login controls, which are now the General section). Reuses
/// `ManagerRow` and the loaded/empty gating from the off-main row build.
struct InstalledPluginsList: View {
    @ObservedObject var model: PluginManagerModel
    /// Resolves a row's id to its in-pane Settings/Debug models (see `LibraryModel`).
    let pluginDetail: (String) -> PluginDetailModels?

    var body: some View {
        Form {
            if !model.isLoaded {
                Section("Plugins") {
                    ForEach(0..<4, id: \.self) { _ in SkeletonPluginRow() }
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
                        // The identity area navigates to the plugin's in-pane
                        // Settings/Debug detail; the trailing toggle and overflow
                        // menu stay outside the link as independent controls.
                        ManagerRow(model: model, row: row, navigatesToDetail: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Installed")
        .navigationDestination(for: String.self) { id in
            if let models = pluginDetail(id) {
                PluginDetailView(name: name(for: id), models: models)
            } else {
                // The plugin went away (e.g. deleted) while the window was open.
                ContentUnavailableView(
                    "Plugin unavailable",
                    systemImage: "puzzlepiece.extension",
                    description: Text("This plugin is no longer available.")
                )
            }
        }
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

    /// The display name for a row id, for the detail's navigation title. Falls
    /// back to the id if the row is gone.
    private func name(for id: String) -> String {
        model.rows.first(where: { $0.id == id })?.name ?? id
    }
}
