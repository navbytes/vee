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
    /// The display name of the store this plugin comes from (e.g. "Public xbar
    /// catalog", or an enterprise store's configured name) — shown on the trust
    /// sheet so provenance isn't misattributed to the public catalog for a
    /// plugin that actually came from a different store.
    public let storeName: String
    public let summary: TrustSummary
    public let warnings: [String]
    public let description: String?
    public let dependencies: [String]
    /// Vee-native features the plugin opts into (search panel, global hotkey),
    /// disclosed alongside its capabilities before install.
    public let features: PluginFeatures
    /// For an update, how the incoming source's trust footprint differs from the
    /// installed one. `nil` for a fresh install (nothing to compare against).
    public let trustDiff: TrustDiff?

    public init(entry: CatalogEntry, source: String, title: String, storeName: String, summary: TrustSummary, warnings: [String], description: String?, dependencies: [String], features: PluginFeatures = PluginFeatures(), trustDiff: TrustDiff? = nil) {
        self.entry = entry
        self.source = source
        self.title = title
        self.storeName = storeName
        self.summary = summary
        self.warnings = warnings
        self.description = description
        self.dependencies = dependencies
        self.features = features
        self.trustDiff = trustDiff
    }
}

/// A transient banner shown over the Discover grid after an install attempt.
public struct CatalogNotice: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case success, failure }
    public let id = UUID()
    public let kind: Kind
    public let message: String
}

/// Backs the plugin browser: fetches the catalog, filters it, and runs the
/// trust-at-install gate before writing a plugin to disk.
@MainActor
public final class PluginBrowserModel: ObservableObject {
    @Published public var entries: [CatalogEntry] = []
    @Published public var search: String = ""
    /// Selected category; empty string means "All".
    @Published public var selectedCategory: String = ""
    /// Selected store; `nil` means "All stores".
    @Published public var selectedStoreID: StoreID?
    @Published public var isLoading = false
    /// A fatal catalog-index load failure — shown full-screen with a Retry, since
    /// there's nothing else to display. Install/fetch problems use ``notice``.
    @Published public var errorMessage: String?
    /// A transient banner over the grid: install success, or an install/fetch
    /// failure that shouldn't blow away the whole catalog.
    @Published public var notice: CatalogNotice?
    @Published public var prompt: InstallPrompt?
    /// Lazily-fetched metadata, keyed by catalog path.
    @Published public var headers: [String: HeaderMetadata] = [:]
    @Published public var trustLevels: [String: TrustLevel] = [:]
    /// Lazily-fetched last-updated dates, keyed by catalog entry id.
    @Published public var lastUpdated: [String: Date] = [:]
    /// Entry ids whose last-updated fetch has been started, so we only make the
    /// (one-call-per-plugin) commits-API request once.
    private var lastUpdatedRequested: Set<String> = []

    /// The configured stores (in Discover order) and a client per store.
    private let stores: [StoreConfig]
    private let clients: [StoreID: CatalogFetching]
    private let pluginsDirectory: String
    private let provenanceStore: ProvenanceStore
    private let onInstalled: () -> Void

    /// Multi-store initializer: builds a client per store via `makeClient`.
    public init(stores: [StoreConfig], makeClient: (StoreConfig) -> CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void) {
        self.stores = stores
        var map: [StoreID: CatalogFetching] = [:]
        for store in stores { map[store.id] = makeClient(store) }
        self.clients = map
        self.pluginsDirectory = pluginsDirectory
        self.provenanceStore = ProvenanceStore(directory: pluginsDirectory)
        self.onInstalled = onInstalled
    }

    /// Single-store convenience (the public catalog), preserved for existing
    /// call sites and tests.
    public convenience init(fetcher: CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void) {
        self.init(stores: [BuiltInStores.xbar], makeClient: { _ in fetcher }, pluginsDirectory: pluginsDirectory, onInstalled: onInstalled)
    }

    /// The client and config for an entry's store.
    private func client(for entry: CatalogEntry) -> CatalogFetching? { clients[entry.storeID] }
    private func store(for entry: CatalogEntry) -> StoreConfig? { stores.first { $0.id == entry.storeID } }

    // Display helpers — fall back to the filename until the header loads. A
    // manifest may supply a title/summary directly, so prefer that.
    func title(for entry: CatalogEntry) -> String {
        let header = headers[entry.id]?.title
        let manifest = entry.manifestTitle
        return [header, manifest].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? entry.filename
    }
    func summary(for entry: CatalogEntry) -> String? { headers[entry.id]?.summary ?? entry.manifestSummary }
    func author(for entry: CatalogEntry) -> String? { headers[entry.id]?.author }
    func trustLevel(for entry: CatalogEntry) -> TrustLevel? { trustLevels[entry.id] }
    /// The effective last-updated date for an entry: the lazily-fetched date
    /// (keyed by `entry.id`, matching how `loadLastUpdated` writes it) if
    /// available, else the catalog-provided static field. Shared by
    /// `freshness(for:)` and the freshness badge so they can never disagree
    /// about which date is "the" date.
    func lastUpdatedDate(for entry: CatalogEntry) -> Date? {
        lastUpdated[entry.id] ?? entry.lastUpdated
    }
    func freshness(for entry: CatalogEntry, now: Date = Date()) -> PluginFreshness? {
        PluginFreshness.classify(lastUpdated: lastUpdatedDate(for: entry), now: now)
    }
    /// The display name of the store an entry came from (for its card chip).
    func storeName(for entry: CatalogEntry) -> String? { store(for: entry)?.displayName }
    /// Whether more than one store is configured (drives the store chip/section).
    var hasMultipleStores: Bool { stores.count > 1 }

    /// Fetches and parses an entry's header + trust once, for display in its card.
    func loadHeader(for entry: CatalogEntry) async {
        guard headers[entry.id] == nil else { return }
        headers[entry.id] = HeaderMetadata() // mark in-flight so we fetch once
        guard let source = try? await client(for: entry)?.fetchSource(entry) else { return }
        headers[entry.id] = HeaderParser.parse(source: source)
        trustLevels[entry.id] = TrustAnalyzer.analyze(TrustParser.parse(source: source)).level
    }

    /// Lazily fetches an entry's last-updated date once, for its freshness
    /// badge. Costs one commits-API call per plugin, so it's guarded to fire a
    /// single time per card and only when the card appears — never eagerly for
    /// the whole grid. Failures leave the date `nil` so the badge is hidden.
    func loadLastUpdated(for entry: CatalogEntry) async {
        guard lastUpdatedRequested.insert(entry.id).inserted else { return }
        guard let date = try? await client(for: entry)?.fetchLastUpdated(entry) else { return }
        lastUpdated[entry.id] = date
    }

    /// Loads every enabled store and merges their entries. A store that fails is
    /// skipped; the full-screen error only shows when *nothing* loaded.
    public func load() async {
        isLoading = true
        errorMessage = nil
        var merged: [CatalogEntry] = []
        var firstError: Error?
        for store in stores where store.isEnabled {
            guard let client = clients[store.id] else { continue }
            do {
                merged += try await client.fetchIndex()
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        entries = merged.sorted { $0.path < $1.path }
        if entries.isEmpty, let firstError {
            errorMessage = CatalogErrorPresenter.message(for: firstError)
        }
        isLoading = false
    }

    /// Re-fetches the catalog from scratch. `load()` only runs once (on first
    /// appearance) and the per-entry caches (header, trust level, freshness)
    /// would otherwise keep stale metadata even after a manual reload, so this
    /// clears them before calling the unchanged `load()`.
    public func refresh() async {
        headers = [:]
        trustLevels = [:]
        lastUpdated = [:]
        lastUpdatedRequested = []
        await load()
    }

    /// A page where a user can read the plugin's source before installing. For a
    /// GitHub store this is the `blob` page; otherwise it's the raw source URL.
    func sourceURL(for entry: CatalogEntry) -> URL? {
        let encoded = entry.path
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let store = store(for: entry), store.kind == .github,
              let owner = store.owner, let repo = store.repo else {
            return entry.rawURL
        }
        return URL(string: "https://github.com/\(owner)/\(repo)/blob/\(store.ref)/\(encoded)") ?? entry.rawURL
    }

    func dismissNotice() { notice = nil }

    /// Clears the active category and search text (the empty-state "show all").
    func clearFilters() {
        selectedCategory = ""
        search = ""
    }

    /// Entries in the selected store scope (all stores when `selectedStoreID` is nil).
    private var storeScopedEntries: [CatalogEntry] {
        guard let selectedStoreID else { return entries }
        return entries.filter { $0.storeID == selectedStoreID }
    }

    /// Categories (within the store scope) with plugin counts, sorted by name.
    var categoriesWithCounts: [(name: String, count: Int)] {
        Dictionary(grouping: storeScopedEntries, by: \.category)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    /// The configured stores with their loaded plugin counts, in Discover order.
    /// Only shown when more than one store is configured.
    var storesWithCounts: [(store: StoreConfig, count: Int)] {
        guard stores.count > 1 else { return [] }
        let counts = Dictionary(grouping: entries, by: \.storeID).mapValues(\.count)
        return stores.map { (store: $0, count: counts[$0.id] ?? 0) }
    }

    /// Entries matching the selected store, category, and search text.
    var visibleEntries: [CatalogEntry] {
        var result = storeScopedEntries
        if !selectedCategory.isEmpty {
            result = result.filter { $0.category == selectedCategory }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter {
                $0.filename.lowercased().contains(q)
                    || $0.category.lowercased().contains(q)
                    || (title(for: $0).lowercased().contains(q))
                    || (summary(for: $0)?.lowercased().contains(q) ?? false)
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

    /// Fetch the source, verify store integrity, and open the trust gate.
    func requestInstall(_ entry: CatalogEntry) async {
        guard let client = client(for: entry) else { return }
        do {
            let source = try await client.fetchSource(entry)
            // Verify the store's integrity guarantees (pinned hash / signature)
            // before anything else. A failure blocks the install with a banner.
            if let store = store(for: entry) {
                let verdict = StoreIntegrity.verify(source: source, entry: entry, store: store, manifestSigningKey: entry.manifestSigningKey)
                guard verdict.passes else {
                    notice = CatalogNotice(kind: .failure, message: "\(entry.filename): \(Self.integrityMessage(verdict))")
                    return
                }
            }
            let declaration = TrustParser.parse(source: source)
            let summary = TrustAnalyzer.analyze(declaration)
            let warnings = summary.warnings + TrustAnalyzer.installWarnings(declaration: declaration, source: source)
            let header = HeaderParser.parse(source: source)
            headers[entry.id] = header
            trustLevels[entry.id] = summary.level
            // When updating an installed plugin, diff the incoming source's
            // trust footprint against the one on disk so silent changes surface.
            let trustDiff = installedSource(for: entry).map { TrustDiff.between(old: $0, new: source) }
            prompt = InstallPrompt(
                entry: entry,
                source: source,
                title: title(for: entry),
                storeName: storeName(for: entry) ?? "Unknown store",
                summary: summary,
                warnings: warnings,
                description: header.summary,
                dependencies: header.dependencies,
                features: PluginFeatures(header: header),
                trustDiff: trustDiff
            )
        } catch {
            // An install/fetch failure is transient — surface it as a banner, not
            // the full-screen catalog-load error (which would hide the grid).
            notice = CatalogNotice(kind: .failure, message: "Couldn't fetch \(entry.filename): \(CatalogErrorPresenter.message(for: error))")
        }
    }

    func confirmInstall() {
        guard let prompt else { return }
        let filename = prompt.entry.filename
        do {
            try PluginInstaller.install(filename: filename, source: prompt.source, into: pluginsDirectory)
            // Record where this came from + its content hash so a later silent
            // change is detectable. Provenance is advisory — a write failure must
            // not block the install itself.
            let provenance = PluginProvenance(filename: filename, sourceURL: prompt.entry.rawURL, source: prompt.source)
            try? provenanceStore.record(provenance)
            notice = CatalogNotice(kind: .success, message: "Installed \(filename)")
            onInstalled()
        } catch {
            notice = CatalogNotice(kind: .failure, message: "Install failed: \(error.localizedDescription)")
        }
        self.prompt = nil
    }

    /// A plain-language reason an integrity check blocked an install.
    private static func integrityMessage(_ verdict: StoreIntegrity.Verdict) -> String {
        switch verdict {
        case .ok: return ""
        case .hashMismatch: return "source doesn't match the catalog's pinned hash"
        case .signatureInvalid: return "the signature didn't verify"
        case .signatureMissing: return "this store requires a signed plugin"
        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isLoading)
                .accessibilityLabel("Refresh catalog")
                .help("Refresh the plugin list (⌘R)")
            }
        }
        .task { if model.entries.isEmpty { await model.load() } }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                NoticeBanner(notice: notice) { model.dismissNotice() }
                    .padding(.top, 8)
                    // Auto-dismiss after a few seconds; re-arms whenever the
                    // notice changes (a newer install replaces an older banner).
                    // `try?` would swallow the CancellationError from a notice
                    // change cancelling this task and still dismiss the NEW
                    // banner it raced with — only dismiss on a real timeout.
                    .task(id: notice.id) {
                        do {
                            try await Task.sleep(for: .seconds(3))
                        } catch {
                            return
                        }
                        model.dismissNotice()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .sheet(item: $model.prompt) { prompt in
            InstallTrustSheet(prompt: prompt, onCancel: { model.prompt = nil }, onInstall: { model.confirmInstall() })
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedCategory) {
            Label("All Plugins", systemImage: "square.grid.2x2.fill")
                .badge(model.entries.count)
                .tag("")
            if !model.storesWithCounts.isEmpty {
                Section("Stores") {
                    storeRow(name: "All Stores", symbol: "square.stack.3d.up.fill", count: model.entries.count, id: nil)
                    ForEach(model.storesWithCounts, id: \.store.id) { item in
                        storeRow(name: item.store.displayName, symbol: "shippingbox.fill", count: item.count, id: item.store.id)
                    }
                }
            }
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

    /// A store scope row (selecting one filters the grid to that store). Uses a
    /// button rather than list selection, which is bound to the category.
    @ViewBuilder
    private func storeRow(name: String, symbol: String, count: Int, id: StoreID?) -> some View {
        Button {
            model.selectedStoreID = id
            model.selectedCategory = ""
        } label: {
            HStack {
                Label(name, systemImage: symbol)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.selectedStoreID == id ? Color.accentColor : Color.primary)
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
            ContentUnavailableView {
                Label("No matching plugins", systemImage: "magnifyingglass")
            } description: {
                if !model.search.isEmpty {
                    Text("Nothing matches “\(model.search)”. Try a shorter or different term, or browse a category.")
                } else {
                    Text("This category has no plugins yet.")
                }
            } actions: {
                if !model.search.isEmpty || !model.selectedCategory.isEmpty {
                    Button("Show All Plugins") { model.clearFilters() }
                        .buttonStyle(.borderedProminent)
                }
            }
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

/// A transient success/failure banner shown over the Discover grid after an
/// install, with a manual dismiss in addition to the auto-timeout.
private struct NoticeBanner: View {
    let notice: CatalogNotice
    let onDismiss: () -> Void

    private var tint: Color { notice.kind == .success ? .green : .red }
    private var symbol: String { notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(notice.message).font(.callout).lineLimit(2)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Corner.callout, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.callout, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
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
                if model.hasMultipleStores, let storeName = model.storeName(for: entry) {
                    Text(storeName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .lineLimit(1)
                }
                if let author = model.author(for: entry) {
                    Text("by \(author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let desc = model.summary(for: entry), !desc.isEmpty {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let level = model.trustLevel(for: entry), level != .undeclared {
                    TrustChip(symbol: level.symbol, label: level.label, tint: level.color).padding(.top, 1)
                }
                SurfaceBadge(surface: entry.manifestSurface).padding(.top, 1)
                if let date = model.lastUpdatedDate(for: entry), let freshness = model.freshness(for: entry) {
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
                if let url = model.sourceURL(for: entry) {
                    Link(destination: url) {
                        Text("View source").font(.caption2)
                    }
                    .help("Open this plugin's source on GitHub")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Corner.card, style: .continuous).fill(.background.secondary))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.card, style: .continuous)
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

/// A "Widget-only" / "Widget" chip when the store declares a plugin's surface
/// (`vee-catalog.json`), so a widget-only plugin — one with no menu-bar
/// presence — is visible *before* install. Hidden for a plain menu plugin or a
/// store that declares nothing (the zero-config public catalog). Matches
/// ``TrustChip``.
private struct SurfaceBadge: View {
    let surface: String?

    var body: some View {
        switch surface {
        case "widget":
            TrustChip(symbol: "square.grid.2x2.fill", label: "Widget-only", tint: .purple)
        case "both":
            TrustChip(symbol: "square.grid.2x2", label: "Widget", tint: .purple)
        default:
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
