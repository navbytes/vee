import SwiftUI
import VeeCatalog
import VeePluginFormat
import VeeTrust

/// A pending install awaiting the user's approval at the trust gate.
public struct InstallPrompt: Identifiable {
    public let id = UUID()
    public let entry: CatalogEntry
    public let source: String
    public let title: String
    public let summary: TrustSummary
    public let warnings: [String]
    public let description: String?
    public let dependencies: [String]
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
    /// Lazily-fetched header metadata, keyed by catalog path.
    @Published public var headers: [String: HeaderMetadata] = [:]

    private let fetcher: CatalogFetching
    private let pluginsDirectory: String
    private let onInstalled: () -> Void

    public init(fetcher: CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void) {
        self.fetcher = fetcher
        self.pluginsDirectory = pluginsDirectory
        self.onInstalled = onInstalled
    }

    // Display helpers — fall back to the filename until the header loads.
    func title(for entry: CatalogEntry) -> String {
        let t = headers[entry.path]?.title
        return (t?.isEmpty == false ? t! : nil) ?? entry.filename
    }
    func summary(for entry: CatalogEntry) -> String? { headers[entry.path]?.summary }
    func author(for entry: CatalogEntry) -> String? { headers[entry.path]?.author }

    /// Fetches and parses an entry's header once, for display in its row.
    func loadHeader(for entry: CatalogEntry) async {
        guard headers[entry.path] == nil else { return }
        headers[entry.path] = HeaderMetadata() // mark in-flight so we fetch once
        if let source = try? await fetcher.fetchSource(entry) {
            headers[entry.path] = HeaderParser.parse(source: source)
        }
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
        return entries.filter {
            $0.filename.lowercased().contains(q)
                || $0.category.lowercased().contains(q)
                || (headers[$0.path]?.title?.lowercased().contains(q) ?? false)
                || (headers[$0.path]?.summary?.lowercased().contains(q) ?? false)
        }
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
            let header = HeaderParser.parse(source: source)
            headers[entry.path] = header
            prompt = InstallPrompt(
                entry: entry,
                source: source,
                title: (header.title?.isEmpty == false ? header.title! : entry.filename),
                summary: summary,
                warnings: warnings,
                description: header.summary,
                dependencies: header.dependencies
            )
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
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.title(for: entry)).fontWeight(.medium)
                                        if let desc = model.summary(for: entry), !desc.isEmpty {
                                            Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        Text(entry.filename + (model.author(for: entry).map { " · \($0)" } ?? ""))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if model.isInstalled(entry) {
                                        Text("Installed").foregroundStyle(.secondary).font(.caption)
                                    } else {
                                        Button("Install") { Task { await model.requestInstall(entry) } }
                                    }
                                }
                                .task { await model.loadHeader(for: entry) }
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
