import SwiftUI
import VeeCatalog
import VeePluginFormat
import VeeTrust

/// A pending install awaiting the user's approval at the trust gate.
public struct InstallPrompt: Identifiable {
    public let id = UUID()
    public let entry: CatalogEntry
    public let source: String
    public let summary: TrustSummary
    public let warnings: [String]
}

/// Backs the plugin browser: fetches the catalog, filters it, and runs the
/// trust-at-install gate before writing a plugin to disk.
@MainActor
public final class PluginBrowserModel: ObservableObject {
    @Published public var entries: [CatalogEntry] = []
    @Published public var search: String = ""
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var prompt: InstallPrompt?

    private let fetcher: CatalogFetching
    private let pluginsDirectory: String
    private let onInstalled: () -> Void

    public init(fetcher: CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void) {
        self.fetcher = fetcher
        self.pluginsDirectory = pluginsDirectory
        self.onInstalled = onInstalled
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await fetcher.fetchIndex()
        } catch {
            errorMessage = "Couldn't load the catalog: \(error.localizedDescription)"
        }
        isLoading = false
    }

    var filtered: [CatalogEntry] {
        guard !search.isEmpty else { return entries }
        let q = search.lowercased()
        return entries.filter { $0.filename.lowercased().contains(q) || $0.category.lowercased().contains(q) }
    }

    var groups: [(category: String, entries: [CatalogEntry])] {
        Dictionary(grouping: filtered, by: \.category)
            .map { (category: $0.key, entries: $0.value) }
            .sorted { $0.category < $1.category }
    }

    func isInstalled(_ entry: CatalogEntry) -> Bool {
        PluginInstaller.isInstalled(filename: entry.filename, in: pluginsDirectory)
    }

    /// Fetch the source and open the trust gate.
    func requestInstall(_ entry: CatalogEntry) async {
        do {
            let source = try await fetcher.fetchSource(entry)
            let declaration = TrustParser.parse(source: source)
            let summary = TrustAnalyzer.analyze(declaration)
            let warnings = summary.warnings + TrustAnalyzer.installWarnings(declaration: declaration, source: source)
            prompt = InstallPrompt(entry: entry, source: source, summary: summary, warnings: warnings)
        } catch {
            errorMessage = "Couldn't fetch \(entry.filename): \(error.localizedDescription)"
        }
    }

    func confirmInstall() {
        guard let prompt else { return }
        do {
            try PluginInstaller.install(filename: prompt.entry.filename, source: prompt.source, into: pluginsDirectory)
            onInstalled()
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }
        self.prompt = nil
    }
}

/// Browses the shared xbar/SwiftBar catalog with search + one-click install,
/// gated by a trust summary.
public struct PluginBrowserView: View {
    @ObservedObject private var model: PluginBrowserModel

    public init(model: PluginBrowserModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discover Plugins").font(.headline)
                Spacer()
                TextField("Search", text: $model.search).frame(width: 200)
            }

            if model.isLoading {
                ProgressView("Loading catalog…").frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load() } }
                }.frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(model.groups, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.entries) { entry in
                                HStack {
                                    Text(entry.filename)
                                    Spacer()
                                    if model.isInstalled(entry) {
                                        Text("Installed").foregroundStyle(.secondary).font(.caption)
                                    } else {
                                        Button("Install") { Task { await model.requestInstall(entry) } }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 300)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task { if model.entries.isEmpty { await model.load() } }
        .sheet(item: $model.prompt) { prompt in
            InstallTrustSheet(prompt: prompt, onCancel: { model.prompt = nil }, onInstall: { model.confirmInstall() })
        }
    }
}
