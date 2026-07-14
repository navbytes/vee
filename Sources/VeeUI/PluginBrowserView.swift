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

/// How the Discover grid orders plugins.
public enum CatalogSortOrder: String, CaseIterable {
    case name
    case updated

    var label: String {
        switch self {
        case .name: return "Name"
        case .updated: return "Recently updated"
        }
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
    /// Selected store; `nil` means "All stores".
    @Published public var selectedStoreID: StoreID?
    @Published public var sortOrder: CatalogSortOrder = .name
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
    /// The on-disk freshness ledger, decoded once at construction (and again
    /// on `refresh()`) rather than on every card appearance — a per-card disk
    /// read/decode of the whole ledger on `@MainActor` was a jank source.
    private var freshnessLedger: [String: CatalogFreshnessStore.Record]

    /// The configured stores (in Discover order) and a client per store.
    private let stores: [StoreConfig]
    private let clients: [StoreID: CatalogFetching]
    private let pluginsDirectory: String
    private let provenanceStore: ProvenanceStore
    private let freshnessStore: CatalogFreshnessStore
    private let onInstalled: () -> Void
    /// Fired after every fresh catalog load: the installed, catalog-tracked
    /// plugins that now have a newer version upstream (possibly empty), plus
    /// the currently installed filename set so the app can prune its
    /// notified-versions ledger — wired by the app to the catalog-update
    /// notification (`Notifier.notifyCatalogUpdates`). Defaults to a no-op so
    /// existing call sites (and every test below) compile unchanged.
    private let onUpdatesFound: ([PluginUpdateCandidate], Set<String>) -> Void

    /// Multi-store initializer: builds a client per store via `makeClient`.
    public init(stores: [StoreConfig], makeClient: (StoreConfig) -> CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void, onUpdatesFound: @escaping ([PluginUpdateCandidate], Set<String>) -> Void = { _, _ in }) {
        self.stores = stores
        var map: [StoreID: CatalogFetching] = [:]
        for store in stores { map[store.id] = makeClient(store) }
        self.clients = map
        self.pluginsDirectory = pluginsDirectory
        self.provenanceStore = ProvenanceStore(directory: pluginsDirectory)
        let freshnessStore = CatalogFreshnessStore(directory: pluginsDirectory)
        self.freshnessStore = freshnessStore
        self.freshnessLedger = freshnessStore.all()
        self.onInstalled = onInstalled
        self.onUpdatesFound = onUpdatesFound
        seedFreshnessCache()
    }

    /// Single-store convenience (the public catalog), preserved for existing
    /// call sites and tests.
    public convenience init(fetcher: CatalogFetching, pluginsDirectory: String, onInstalled: @escaping () -> Void, onUpdatesFound: @escaping ([PluginUpdateCandidate], Set<String>) -> Void = { _, _ in }) {
        self.init(stores: [BuiltInStores.xbar], makeClient: { _ in fetcher }, pluginsDirectory: pluginsDirectory, onInstalled: onInstalled, onUpdatesFound: onUpdatesFound)
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

    /// Seeds ``lastUpdated``/``lastUpdatedRequested`` from ``freshnessLedger``
    /// (persists across launches and `refresh()`), skipping any record older
    /// than ``CatalogFreshnessStore/ttl`` — an expired record is left
    /// unseeded so the entry's first `loadLastUpdated` still falls through to
    /// a real network fetch instead of being treated as already-served.
    private func seedFreshnessCache(now: Date = Date()) {
        for (id, record) in freshnessLedger where now.timeIntervalSince(record.fetchedAt) < CatalogFreshnessStore.ttl {
            lastUpdated[id] = record.date
            lastUpdatedRequested.insert(id)
        }
    }

    /// Lazily fetches an entry's last-updated date once, for its freshness
    /// badge. `seedFreshnessCache()` already served any fresh on-disk record
    /// into `lastUpdated`/`lastUpdatedRequested`, so this only needs the
    /// in-memory guard — no disk I/O on the hot per-card path. Guarded to
    /// fire a single time per card and only when the card appears — never
    /// eagerly for the whole grid. Failures leave the date `nil` so the badge
    /// is hidden.
    func loadLastUpdated(for entry: CatalogEntry) async {
        guard lastUpdatedRequested.insert(entry.id).inserted else { return }
        guard let date = try? await client(for: entry)?.fetchLastUpdated(entry) else { return }
        lastUpdated[entry.id] = date
        let fetchedAt = Date()
        freshnessLedger[entry.id] = CatalogFreshnessStore.Record(date: date, fetchedAt: fetchedAt)
        try? freshnessStore.record(entryID: entry.id, date: date, fetchedAt: fetchedAt)
    }

    /// Eagerly backfills the last-updated date for every entry in `entries`,
    /// used when the user switches to "Recently updated" sort — normal
    /// browsing still relies on ``loadLastUpdated(for:)`` firing lazily as
    /// each card scrolls into view. Bounded to a handful of concurrent
    /// fetches (rather than fully serial) so a cold cache on a large catalog
    /// doesn't chain one commits-API call at a time — still ultimately capped
    /// by GitHub's real unauthenticated rate limit, and best-effort (a failed
    /// fetch just leaves that entry's date `nil`, same as `loadLastUpdated`).
    func ensureLastUpdatedLoaded(for entries: [CatalogEntry]) async {
        let maxConcurrent = 4
        await withTaskGroup(of: Void.self) { group in
            var iterator = entries.makeIterator()
            func addNext() {
                guard let entry = iterator.next() else { return }
                group.addTask { await self.loadLastUpdated(for: entry) }
            }
            for _ in 0..<maxConcurrent { addNext() }
            while await group.next() != nil { addNext() }
        }
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
        if !entries.isEmpty {
            // Persist the index so the app's launch-time update scan can run
            // against it with zero network — Vee never fetches at launch.
            try? CatalogSnapshotStore(directory: pluginsDirectory).save(entries)
        }
        reportPendingUpdates()
    }

    /// Checks installed, catalog-provenance-tracked plugins against the
    /// entries just loaded for a newer version, and hands the result (plus the
    /// installed filename set, for ledger pruning) to `onUpdatesFound` — even
    /// when no updates were found, so the app-side ledger tracks uninstalls.
    /// A plugin with no provenance record (never installed through Discover)
    /// can never appear here — `pendingUpdates` only scans `provenanceStore`'s
    /// ledger. Uses only the already-cached `lastUpdatedDate(for:)` (seeded
    /// from the on-disk freshness ledger or a manifest-pinned hash) — never
    /// triggers a new network fetch — so both the view's cold-open `load()`
    /// and the manual-refresh `refresh()` (which calls through to `load()`)
    /// report the same way, for free.
    private func reportPendingUpdates() {
        let installed = Array(provenanceStore.all().values)
        guard !installed.isEmpty else { return }
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: entries) { lastUpdatedDate(for: $0) }
        onUpdatesFound(candidates, Set(installed.map(\.filename)))
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
        // Reseed from the in-memory ledger (no disk read) rather than leaving
        // it empty: a still-fresh record should keep being served without a
        // wasted re-fetch, while an expired one is skipped so this refresh is
        // exactly what corrects a stale badge (fix for the freshness cache
        // that used to never expire).
        seedFreshnessCache()
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

    /// Entries matching the selected store, category, and search text, in the
    /// current sort order.
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
        return sorted(result)
    }

    /// `visibleEntries` grouped by category (sorted by category name),
    /// preserving each entry's position within the current sort order. Lives on
    /// the model (not the view) so the grouping/sort-within-section logic is
    /// unit-testable.
    var sectionedEntries: [(category: String, entries: [CatalogEntry])] {
        Dictionary(grouping: visibleEntries, by: \.category)
            .map { (category: $0.key, entries: $0.value) }
            .sorted { $0.category < $1.category }
    }

    /// Sorts `entries` by the current `sortOrder`. `.updated` sorts
    /// newest-first with `nil`-date entries pushed to the end, falling back to
    /// `.name` order within that "unknown date" group so it isn't left
    /// arbitrary/unstable.
    private func sorted(_ entries: [CatalogEntry]) -> [CatalogEntry] {
        switch sortOrder {
        case .name:
            return entries.sorted { title(for: $0).localizedCaseInsensitiveCompare(title(for: $1)) == .orderedAscending }
        case .updated:
            return entries.sorted { a, b in
                let dateA = lastUpdatedDate(for: a)
                let dateB = lastUpdatedDate(for: b)
                switch (dateA, dateB) {
                case let (a?, b?): return a > b
                case (nil, nil): return title(for: a).localizedCaseInsensitiveCompare(title(for: b)) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
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

/// The Discover catalog browser as a **single-column** view (no
/// `NavigationSplitView`), so it can be embedded in the consolidated window's
/// detail pane — which is itself already inside a `NavigationSplitView` — without
/// nesting split views. The category/store filter that used to be the standalone
/// window's sidebar is surfaced here as toolbar menus, driven by the same
/// `model.selectedCategory`/`selectedStoreID`. The grid, loading/empty/error
/// states, the install-notice banner, and the trust-at-install sheet are shared
/// with the (now dead-code) standalone `PluginBrowserView`, which wraps this.
public struct DiscoverContentView: View {
    @ObservedObject private var model: PluginBrowserModel
    /// Local to the view — the popover's own filter text doesn't need to
    /// survive beyond the popover being open.
    @State private var showingCategoryPopover = false
    @State private var categoryFilterText = ""

    public init(model: PluginBrowserModel) {
        self.model = model
    }

    public var body: some View {
        detail
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search plugins")
            .toolbar {
                // The store scope only exists when more than one store is
                // configured (mirrors the old sidebar's Stores section).
                if !model.storesWithCounts.isEmpty {
                    ToolbarItem(placement: .automatic) { storeMenu }
                }
                ToolbarItem(placement: .automatic) { categoryFilterButton }
                ToolbarItem(placement: .automatic) { sortMenu }
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
            // Only "Recently updated" needs every entry's date up front —
            // normal browsing relies on each card's own lazy `.task` firing as
            // it scrolls into view. Re-runs (and progressively re-sorts, for
            // free via the @Published date updates) only when the sort order
            // itself changes.
            .task(id: model.sortOrder) {
                guard model.sortOrder == .updated else { return }
                await model.ensureLastUpdatedLoaded(for: model.visibleEntries)
            }
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

    /// The category filter, as a toolbar button presenting a type-to-filter
    /// popover. A plain `Menu`/`Picker` (the previous design) doesn't scale
    /// once a catalog has many categories. Replaces the sidebar's Categories
    /// section.
    private var categoryFilterButton: some View {
        Button {
            showingCategoryPopover = true
        } label: {
            Label(model.selectedCategory.isEmpty ? "All Categories" : model.selectedCategory,
                  systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter by category")
        .popover(isPresented: $showingCategoryPopover) {
            categoryFilterPopover
        }
    }

    private var filteredCategories: [(name: String, count: Int)] {
        guard !categoryFilterText.isEmpty else { return model.categoriesWithCounts }
        return model.categoriesWithCounts.filter { $0.name.localizedCaseInsensitiveContains(categoryFilterText) }
    }

    private var categoryFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter categories", text: $categoryFilterText)
                    .textFieldStyle(.plain)
            }
            .padding(Space.sm)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    categoryFilterRow(name: "All Categories", isSelected: model.selectedCategory.isEmpty) {
                        model.selectedCategory = ""
                    }
                    if filteredCategories.isEmpty {
                        Text("No categories match “\(categoryFilterText)”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(Space.sm)
                    } else {
                        ForEach(filteredCategories, id: \.name) { cat in
                            categoryFilterRow(name: "\(cat.name) (\(cat.count))", isSelected: model.selectedCategory == cat.name) {
                                model.selectedCategory = cat.name
                            }
                        }
                    }
                }
                .padding(.vertical, Space.xs)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 230)
    }

    private func categoryFilterRow(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingCategoryPopover = false
            categoryFilterText = ""
        } label: {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 5)
    }

    /// The sort control, as a toolbar menu bound to `model.sortOrder`.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sortOrder) {
                ForEach(CatalogSortOrder.allCases, id: \.self) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort plugins")
    }

    /// The store scope, as a toolbar menu. Uses buttons (not a `Picker`) so
    /// picking a store also resets the category — matching the old sidebar's
    /// store rows, whose selection was independent of the category list.
    private var storeMenu: some View {
        Menu {
            Button {
                model.selectedStoreID = nil
                model.selectedCategory = ""
            } label: {
                storeMenuRow(name: "All Stores", isSelected: model.selectedStoreID == nil)
            }
            ForEach(model.storesWithCounts, id: \.store.id) { item in
                Button {
                    model.selectedStoreID = item.store.id
                    model.selectedCategory = ""
                } label: {
                    storeMenuRow(name: "\(item.store.displayName) (\(item.count))",
                                 isSelected: model.selectedStoreID == item.store.id)
                }
            }
        } label: {
            Label(storeMenuLabel, systemImage: "shippingbox")
        }
        .help("Filter by store")
    }

    @ViewBuilder
    private func storeMenuRow(name: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    private var storeMenuLabel: String {
        guard let id = model.selectedStoreID,
              let store = model.storesWithCounts.first(where: { $0.store.id == id })?.store else {
            return "All Stores"
        }
        return store.displayName
    }

    /// The shared column spec for every Discover grid (skeleton, sectioned,
    /// and flat) — kept in one place so the three branches below can't drift.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: Space.md)]
    }

    @ViewBuilder
    private var detail: some View {
        if model.isLoading {
            // Skeleton cards in the real grid, so the catalog settles into place
            // instead of the whole pane flipping from a centered spinner to a full
            // grid (the fetch can take a beat over the network).
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: Space.md) {
                    ForEach(0..<6, id: \.self) { _ in SkeletonPluginCard() }
                }
                .padding(Space.lg)
            }
            .navigationTitle("Discover")
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
        } else if model.selectedCategory.isEmpty {
            // "All Categories" — group into sections so a large catalog scans
            // by category instead of one undifferentiated wall of cards. A
            // single category is already a scoped list, so it stays flat (a
            // lone repeated header would just be noise).
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.lg) {
                    ForEach(model.sectionedEntries, id: \.category) { section in
                        VStack(alignment: .leading, spacing: Space.sm) {
                            CategorySectionHeader(name: section.category, count: section.entries.count)
                            LazyVGrid(columns: gridColumns, spacing: Space.md) {
                                ForEach(section.entries) { entry in
                                    PluginCard(model: model, entry: entry)
                                        .task { await model.loadHeader(for: entry) }
                                }
                            }
                        }
                    }
                }
                .padding(Space.lg)
            }
            .navigationTitle(model.visibleTitle)
            .navigationSubtitle("\(model.visibleEntries.count) plugins")
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: Space.md) {
                    ForEach(model.visibleEntries) { entry in
                        PluginCard(model: model, entry: entry)
                            .task { await model.loadHeader(for: entry) }
                    }
                }
                .padding(Space.lg)
            }
            .navigationTitle(model.visibleTitle)
            .navigationSubtitle("\(model.visibleEntries.count) plugins")
        }
    }
}

/// The standalone Discover window's root. Retained as **dead-but-compiling**
/// code after the catalog browser moved into the consolidated window
/// (`LibraryView` → `.discover`); it simply hosts `DiscoverContentView` at the
/// window's minimum size.
public struct PluginBrowserView: View {
    @ObservedObject private var model: PluginBrowserModel

    public init(model: PluginBrowserModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            DiscoverContentView(model: model)
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

/// A category header above one section of the grouped-by-category Discover
/// grid — muted, uppercase, matching the weight of a section label rather
/// than competing with the plugin cards below it.
private struct CategorySectionHeader: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                Text(model.title(for: entry)).font(TypeRole.cardTitle).lineLimit(1)
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
                // One ranked badge row instead of a vertical ladder of
                // same-weight pills: a filled chip for state that matters (trust,
                // widget-only), muted text for metadata (freshness).
                HStack(spacing: Space.sm) {
                    if let level = model.trustLevel(for: entry), level != .undeclared {
                        TrustChip(symbol: level.symbol, label: level.label, tint: level.color)
                    }
                    SurfaceBadge(surface: entry.manifestSurface)
                    if let date = model.lastUpdatedDate(for: entry), let freshness = model.freshness(for: entry) {
                        FreshnessBadge(date: date, freshness: freshness)
                    }
                }
                .padding(.top, 2)
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
        .padding(Space.md)
        .veeCardSurface(hovering: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .task { await model.loadLastUpdated(for: entry) }
    }
}

/// A placeholder card shown while the catalog loads — neutral bars in
/// ``PluginCard``'s shape (tile · title/lines/badge · action), on the same
/// `veeCardSurface`, so the grid holds its layout instead of popping in.
private struct SkeletonPluginCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hairline)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(Palette.hairline).frame(width: 128, height: 11)
                Capsule().fill(Palette.hairline).frame(width: 180, height: 8)
                Capsule().fill(Palette.hairline).frame(width: 150, height: 8)
                Capsule().fill(Palette.hairline).frame(width: 72, height: 16).padding(.top, 2)
            }
            Spacer(minLength: 6)
            Capsule().fill(Palette.hairline).frame(width: 58, height: 22)
        }
        .padding(Space.md)
        .veeCardSurface()
        .accessibilityHidden(true)
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
        // Freshness is metadata, not state — a muted MetaChip, not a filled pill.
        MetaChip(symbol: "clock", label: "Updated \(relative)", tint: tint)
    }
}
