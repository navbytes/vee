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
    /// For an update, how the incoming source's trust footprint differs from the
    /// installed one. `nil` for a fresh install (nothing to compare against).
    public let trustDiff: TrustDiff?

    public init(entry: CatalogEntry, source: String, title: String, summary: TrustSummary, warnings: [String], description: String?, dependencies: [String], trustDiff: TrustDiff? = nil) {
        self.entry = entry
        self.source = source
        self.title = title
        self.summary = summary
        self.warnings = warnings
        self.description = description
        self.dependencies = dependencies
        self.trustDiff = trustDiff
    }
}

/// Backs the plugin browser: fetches the catalog, filters it, and runs the
/// trust-at-install gate before writing a plugin to disk.
@MainActor
public final class PluginBrowserModel: ObservableObject {
    @Published public var entries: [CatalogEntry] = []
    @Published public var search: String = ""
    /// Selected category; empty string means "All".
    @Published public var selectedCategory: String = ""
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var prompt: InstallPrompt?
    /// Lazily-fetched metadata, keyed by catalog path.
    @Published public var headers: [String: HeaderMetadata] = [:]
    @Published public var trustLevels: [String: TrustLevel] = [:]
    /// Lazily-fetched last-updated dates, keyed by catalog path.
    @Published public var lastUpdated: [String: Date] = [:]
    /// Paths whose last-updated fetch has been started, so we only make the
    /// (one-call-per-plugin) commits-API request once.
    private var lastUpdatedRequested: Set<String> = []

    private let fetcher: CatalogFetching
    private let pluginsDirectory: String
    private let provenanceStore: ProvenanceStore
    private let onInstalled: () -> Void

    public init(fetcher: CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void) {
        self.fetcher = fetcher
        self.pluginsDirectory = pluginsDirectory
        self.provenanceStore = ProvenanceStore(directory: pluginsDirectory)
        self.onInstalled = onInstalled
    }

    // Display helpers — fall back to the filename until the header loads.
    func title(for entry: CatalogEntry) -> String {
        let t = headers[entry.path]?.title
        return (t?.isEmpty == false ? t! : nil) ?? entry.filename
    }
    func summary(for entry: CatalogEntry) -> String? { headers[entry.path]?.summary }
    func author(for entry: CatalogEntry) -> String? { headers[entry.path]?.author }
    func trustLevel(for entry: CatalogEntry) -> TrustLevel? { trustLevels[entry.path] }
    func freshness(for entry: CatalogEntry, now: Date = Date()) -> PluginFreshness? {
        PluginFreshness.classify(lastUpdated: lastUpdated[entry.path], now: now)
    }

    /// Fetches and parses an entry's header + trust once, for display in its card.
    func loadHeader(for entry: CatalogEntry) async {
        guard headers[entry.path] == nil else { return }
        headers[entry.path] = HeaderMetadata() // mark in-flight so we fetch once
        guard let source = try? await fetcher.fetchSource(entry) else { return }
        headers[entry.path] = HeaderParser.parse(source: source)
        trustLevels[entry.path] = TrustAnalyzer.analyze(TrustParser.parse(source: source)).level
    }

    /// Lazily fetches an entry's last-updated date once, for its freshness
    /// badge. Costs one commits-API call per plugin, so it's guarded to fire a
    /// single time per card and only when the card appears — never eagerly for
    /// the whole grid. Failures leave the date `nil` so the badge is hidden.
    func loadLastUpdated(for entry: CatalogEntry) async {
        guard lastUpdatedRequested.insert(entry.path).inserted else { return }
        guard let date = try? await fetcher.fetchLastUpdated(entry) else { return }
        lastUpdated[entry.path] = date
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

    /// Categories with plugin counts, sorted by name.
    var categoriesWithCounts: [(name: String, count: Int)] {
        Dictionary(grouping: entries, by: \.category)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    /// Entries matching the selected category and search text.
    var visibleEntries: [CatalogEntry] {
        var result = entries
        if !selectedCategory.isEmpty {
            result = result.filter { $0.category == selectedCategory }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter {
                $0.filename.lowercased().contains(q)
                    || $0.category.lowercased().contains(q)
                    || (headers[$0.path]?.title?.lowercased().contains(q) ?? false)
                    || (headers[$0.path]?.summary?.lowercased().contains(q) ?? false)
            }
        }
        return result
    }

    var visibleTitle: String { selectedCategory.isEmpty ? "All Plugins" : selectedCategory }

    func isInstalled(_ entry: CatalogEntry) -> Bool {
        PluginInstaller.isInstalled(filename: entry.filename, in: pluginsDirectory)
    }

    /// Provenance status of an installed plugin: `.verified` when its on-disk
    /// source still matches what was recorded at install, `.modified` when it has
    /// changed since (local edit or a re-install from a different source), and
    /// `.unknown` when there's no record (e.g. a hand-authored plugin).
    func provenanceStatus(for entry: CatalogEntry) -> ProvenanceStatus {
        let record = provenanceStore.record(for: entry.filename)
        let path = (pluginsDirectory as NSString).appendingPathComponent(entry.filename)
        let current = try? String(contentsOfFile: path, encoding: .utf8)
        return ProvenanceStatus.evaluate(record: record, currentSource: current)
    }

    /// The installed plugin's source on disk, if any — used to diff against an
    /// incoming update at the trust gate.
    private func installedSource(for entry: CatalogEntry) -> String? {
        let path = (pluginsDirectory as NSString).appendingPathComponent(entry.filename)
        return try? String(contentsOfFile: path, encoding: .utf8)
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
            trustLevels[entry.path] = summary.level
            // When updating an installed plugin, diff the incoming source's
            // trust footprint against the one on disk so silent changes surface.
            let trustDiff = installedSource(for: entry).map { TrustDiff.between(old: $0, new: source) }
            prompt = InstallPrompt(
                entry: entry,
                source: source,
                title: (header.title?.isEmpty == false ? header.title! : entry.filename),
                summary: summary,
                warnings: warnings,
                description: header.summary,
                dependencies: header.dependencies,
                trustDiff: trustDiff
            )
        } catch {
            errorMessage = "Couldn't fetch \(entry.filename): \(error.localizedDescription)"
        }
    }

    func confirmInstall() {
        guard let prompt else { return }
        do {
            try PluginInstaller.install(filename: prompt.entry.filename, source: prompt.source, into: pluginsDirectory)
            // Record where this came from + its content hash so a later silent
            // change is detectable. Provenance is advisory — a write failure must
            // not block the install itself.
            let provenance = PluginProvenance(filename: prompt.entry.filename, sourceURL: prompt.entry.rawURL, source: prompt.source)
            try? provenanceStore.record(provenance)
            onInstalled()
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }
        self.prompt = nil
    }
}

/// Browses the shared xbar/SwiftBar catalog: a category sidebar and a grid of
/// plugin cards, each with a trust chip, gated by a trust-at-install sheet.
public struct PluginBrowserView: View {
    @ObservedObject private var model: PluginBrowserModel

    public init(model: PluginBrowserModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 500)
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search plugins")
        .task { if model.entries.isEmpty { await model.load() } }
        .sheet(item: $model.prompt) { prompt in
            InstallTrustSheet(prompt: prompt, onCancel: { model.prompt = nil }, onInstall: { model.confirmInstall() })
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedCategory) {
            Label("All Plugins", systemImage: "square.grid.2x2.fill")
                .badge(model.entries.count)
                .tag("")
            Section("Categories") {
                ForEach(model.categoriesWithCounts, id: \.name) { cat in
                    Label(cat.name, systemImage: CategoryStyle.symbol(for: cat.name))
                        .badge(cat.count)
                        .tag(cat.name)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .navigationTitle("Discover")
    }

    @ViewBuilder
    private var detail: some View {
        if model.isLoading {
            ProgressView("Loading catalog…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load plugins", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.load() } }.buttonStyle(.borderedProminent)
            }
        } else if model.visibleEntries.isEmpty {
            ContentUnavailableView.search
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 12)], spacing: 12) {
                    ForEach(model.visibleEntries) { entry in
                        PluginCard(model: model, entry: entry)
                            .task { await model.loadHeader(for: entry) }
                    }
                }
                .padding(16)
            }
            .navigationTitle(model.visibleTitle)
            .navigationSubtitle("\(model.visibleEntries.count) plugins")
        }
    }
}

/// One plugin card in the Discover grid.
private struct PluginCard: View {
    @ObservedObject var model: PluginBrowserModel
    let entry: CatalogEntry
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PluginTile(symbol: CategoryStyle.symbol(for: entry.category), tint: CategoryStyle.tint(for: entry.category))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title(for: entry)).font(.headline).lineLimit(1)
                if let author = model.author(for: entry) {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let desc = model.summary(for: entry), !desc.isEmpty {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let level = model.trustLevel(for: entry), level != .undeclared {
                    TrustChip(symbol: level.symbol, label: level.label, tint: level.color).padding(.top, 1)
                }
                if let date = model.lastUpdated[entry.path], let freshness = model.freshness(for: entry) {
                    FreshnessBadge(date: date, freshness: freshness).padding(.top, 1)
                }
            }

            Spacer(minLength: 6)

            VStack(spacing: 4) {
                if model.isInstalled(entry) {
                    Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    ProvenanceBadge(status: model.provenanceStatus(for: entry))
                    // Re-fetch the latest catalog source and overwrite in place,
                    // through the same trust gate.
                    Button("Update") { Task { await model.requestInstall(entry) } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("Install") { Task { await model.requestInstall(entry) } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hovering ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 8, y: 3)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .task { await model.loadLastUpdated(for: entry) }
    }
}

/// A subtle "Verified"/"Modified" chip for an installed catalog plugin, driven
/// by its recorded provenance. Hidden entirely when there's no record
/// (`.unknown`), so hand-authored plugins show nothing. Matches ``TrustChip``.
private struct ProvenanceBadge: View {
    let status: ProvenanceStatus

    var body: some View {
        switch status {
        case .verified:
            TrustChip(symbol: "checkmark.seal.fill", label: "Verified", tint: .green)
        case .modified:
            TrustChip(symbol: "exclamationmark.triangle.fill", label: "Modified", tint: .orange)
        case .unknown:
            EmptyView()
        }
    }
}

/// A small "Updated 3y ago" chip on a plugin card, tinted by how fresh the
/// plugin is. Matches the ``TrustChip`` capsule styling.
private struct FreshnessBadge: View {
    let date: Date
    let freshness: PluginFreshness

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var tint: Color {
        switch freshness {
        case .fresh: return .green
        case .aging: return .orange
        case .stale: return .secondary
        }
    }

    var body: some View {
        let relative = Self.relative.localizedString(for: date, relativeTo: Date())
        TrustChip(symbol: "clock", label: "Updated \(relative)", tint: tint)
    }
}
