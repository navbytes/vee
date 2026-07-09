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

    public init(
        section: LibrarySection = .installed,
        manager: PluginManagerModel,
        general: GeneralSettingsModel,
        stores: StoresSettingsModel,
        variables: VariablesEditorModel,
        browser: PluginBrowserModel
    ) {
        self.section = section
        self.manager = manager
        self.general = general
        self.stores = stores
        self.variables = variables
        self.browser = browser
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
                    sidebarRow(.installed)
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
            InstalledPluginsList(model: model.manager)
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

/// The Installed section: the plugin list extracted from `PluginManagerView`
/// (minus the folder/login controls, which are now the General section). Reuses
/// `ManagerRow` and the loaded/empty gating from the off-main row build.
struct InstalledPluginsList: View {
    @ObservedObject var model: PluginManagerModel

    var body: some View {
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
        }
        .formStyle(.grouped)
        .navigationTitle("Installed")
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
}
