import AppKit
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeeMenu
import VeeSearch
import VeePreferences
import VeeTrust
import VeeCatalog
import VeeUI
import VeeWidgetShared
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The application delegate. Owns the always-present Vee menu and one coordinator
/// per enabled plugin, watches the plugins directory, and drives the plugin
/// manager.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    // Rebuilt once the login-shell PATH is resolved (see applicationDidFinishLaunching).
    private var baseEnvironment = ProcessInfo.processInfo.environment
    private var runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner()))
    private var coordinators: [String: PluginCoordinator] = [:]
    /// The Plugin Manager model while its window is open, held weakly so live
    /// per-plugin error updates can be pushed into it. Nil when the window is closed.
    private weak var currentManagerModel: PluginManagerModel?
    /// The Discover model, retained across window opens so the fetched catalog
    /// (and per-plugin freshness/header caches) survives a close/reopen instead
    /// of re-fetching the network from scratch every time. Rebuilt only when the
    /// store set or plugins directory changes (see `openBrowser`).
    private var cachedBrowserModel: PluginBrowserModel?
    private var cachedBrowserStores: [StoreConfig]?
    private var cachedBrowserDirectory: String?
    private var ephemerals: [String: StatusItemController] = [:]
    /// Per-key deadline task for an ephemeral item's `exitafter=`. Re-setting
    /// an ephemeral item under the same name must cancel and replace the OLD
    /// deadline — otherwise it still fires on the old schedule and removes the
    /// REPLACED content early. See `showEphemeral`.
    private var ephemeralExpiries: [String: Task<Void, Never>] = [:]
    /// Per-file identity of the currently loaded plugins; a change here
    /// (including an in-place edit) triggers a rebuild. See `reload()`.
    private var loadedSignature: [String: PluginChangeSnapshot.FileIdentity] = [:]
    private var watcher: PluginDirectoryWatcher?
    private var wakeMonitor: WakeMonitor?
    private var mainMenu: MainMenuController?
    private var generalSettingsModel: GeneralSettingsModel?
    private let prefs = AppPreferences.shared
    private let log = VeeLog.make("app-controller")
    /// Builds the per-plugin secret store `reconcileDiskState()` clears a
    /// Keychain secret through. Defaults to the real Keychain; a test injects
    /// an in-memory fake — the same seam `VariablesEditorModel` already uses,
    /// since real Keychain access in a plain `swift test` binary is
    /// unreliable/prompts (there's no entitlement/signing for it there).
    private let secretStoreFactory: (PluginID) -> SecretStoring

    /// Live "combine everything into one menu bar item" toggle (issue #71 —
    /// one icon total in compact mode, not two side by side). Removed at
    /// `applicationWillTerminate` for symmetry with the app's other observers.
    private var compactModeObserverToken: NSObjectProtocol?

    /// The app-level "bring every detached window to the front" hotkey: the
    /// `GlobalHotKeys` token while one is bound, and what binding it did — the
    /// status General settings shows. Unbound by default, so most launches
    /// register nothing and both stay at their empty state.
    private var focusWindowsHotKeyID: UInt32?
    private var focusWindowsHotkeyStatus: HotkeyStatus = .none

    private var directory: String = PluginsDirectory.resolve()

    /// Filename → when `reconcileDiskState` first saw it missing from
    /// `directory`, for names it hasn't collected yet. Cleared the moment the
    /// file comes back. See `deletionGracePeriod`.
    ///
    /// Deliberately in-memory: it exists to ride out a *transient* absence, and
    /// every transient absence resolves in seconds. Losing it at quit only means
    /// a genuinely-deleted plugin's state waits out one more grace period after
    /// the next launch, which is the harmless direction for this to fail in —
    /// the same "safe-but-leaky beats false-wipe" trade the guards above make.
    private var missingSince: [String: Date] = [:]

    /// How long a plugin's file must stay missing before its irreversible state
    /// — Keychain secrets above all — is destroyed.
    ///
    /// Long enough to cover every transient absence: an editor's save window is
    /// milliseconds, a volume remount seconds, a drag-out-and-back a few. Short
    /// enough that the risk it introduces stays remote: while state lingers, a
    /// NEW plugin installed under the same filename inherits the old one's
    /// settings and secrets. That is the hazard this trades against, and it
    /// needs a same-name reinstall inside the window to happen at all —
    /// far rarer than an editor save.
    ///
    /// Injectable (not a buried literal) for the same reason
    /// `SystemProcessRunner.defaultDetachedTimeout` is: a test asserting the GC
    /// itself should not have to wait out five real minutes.
    private let deletionGracePeriod: TimeInterval

    /// Widget-snapshot publishing state/policy (coalesced writes, metered
    /// WidgetKit reloads) — see `WidgetSnapshotPublisher`. Constructed here with
    /// the production effects so the publisher itself stays WidgetKit-free.
    private let widgetPublisher = WidgetSnapshotPublisher(
        write: { VeeWidgetSharing.shared.write($0) },
        requestReload: {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    )

    /// The running controller, so App Intents (Shortcuts/Spotlight) can drive it.
    public static weak var shared: AppController?

    public init(secretStoreFactory: ((PluginID) -> SecretStoring)? = nil, deletionGracePeriod: TimeInterval = 300) {
        self.secretStoreFactory = secretStoreFactory ?? { KeychainSecretStore(pluginID: $0.rawValue) }
        self.deletionGracePeriod = deletionGracePeriod
        super.init()
        Self.shared = self
    }

    // MARK: - Intent entry points (Shortcuts / Spotlight)

    /// Re-runs every enabled plugin. Exposed for App Intents.
    public func intentRefreshAll() { refreshAll() }

    /// Re-runs one plugin by name (its filename id). Returns whether it matched.
    @discardableResult
    public func intentRefresh(name: String) -> Bool {
        guard let coordinator = coordinators[name] else { return false }
        coordinator.forceRefresh()
        return true
    }

    /// Enables or disables one plugin by name. Exposed for App Intents.
    public func intentSetEnabled(_ enabled: Bool, name: String) { setEnabled(enabled, id: name) }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        PluginsDirectory.ensureExists(directory)
        log.info("plugins directory: \(self.directory, privacy: .public)")
        sweepLegacyActivities()

        installAppMenu()

        mainMenu = MainMenuController(
            onManager: { [weak self] in self?.openManager() },
            onDiscover: { [weak self] in self?.openBrowser() },
            onPreferences: { [weak self] in self?.openPreferences() },
            onRefreshAll: { [weak self] in self?.refreshAll() },
            onOpenFolder: { [weak self] in self?.openFolder() }
        )
        // Issue #71 ("one icon total"): fold the app item's own controls under
        // the compact item's shared icon when compact mode is already on at
        // launch, and keep reconciling live afterward — see `applyCompactMode`.
        applyCompactMode(prefs.compactMenuBar)
        compactModeObserverToken = NotificationCenter.default.addObserver(
            forName: AppPreferences.compactMenuBarDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyCompactMode(self?.prefs.compactMenuBar ?? false) }
        }
        registerFocusWindowsHotKey()
        // Register the notification delegate + action categories now, but defer
        // the permission prompt until a plugin actually posts an alert, so the
        // system dialog appears in context rather than at a cold launch.
        Notifier.prepare()
        // Wire the plugin-alert action buttons to the live coordinators:
        // Re-run refreshes the plugin; Open-log opens its debug console.
        // Tapping a catalog-update nudge opens Discover, the same way the
        // menu's Discover item and first-run do.
        Notifier.configure(
            onRerun: { [weak self] id in self?.coordinators[id]?.forceRefresh() },
            onOpenLog: { [weak self] id in self?.coordinators[id]?.showDebugConsole() },
            onOpenDiscover: { [weak self] in self?.openBrowser() }
        )

        presentFirstRunIfNeeded()
        scanCatalogSnapshotForUpdates()

        // Resolve the user's real login-shell PATH before loading plugins, so a
        // Finder/Dock launch finds Homebrew/pyenv/asdf/nvm binaries just like a
        // Terminal launch would. The Vee menu is already up; plugins appear once
        // this returns (a short, timed-out shell call).
        // Refresh immediately when the Control Center control fires while Vee is
        // already running. (A cold start needs no flag: the control launches Vee
        // via openAppWhenRun, and Vee refreshes every plugin on launch.)
        registerControlRefreshObserver()
        // Per-plugin widget card actions (refresh/shortcut buttons) — see
        // `widgetActionRequestFired()`.
        registerWidgetActionObserver()

        Task { @MainActor in
            self.baseEnvironment = await ShellPathResolver.resolvedEnvironment()
            self.runtime = PluginRuntime(executor: PluginExecutor(runner: SystemProcessRunner(), baseEnvironment: self.baseEnvironment))
            self.reload()
            self.startWatching()
            // Service a request written while the app was closed (the widget
            // intent's openAppWhenRun just launched us for it) — the Darwin
            // notify that accompanied it fired before any observer existed to
            // hear it, so it must be picked up explicitly, once, here.
            self.widgetActionRequestFired()
        }

        let monitor = WakeMonitor { [weak self] in self?.refreshAll() }
        monitor.start()
        wakeMonitor = monitor
    }

    /// Clears the launch-on-demand XPC activities earlier versions registered,
    /// for every plugin Vee has **ever** loaded — not just the ones installed
    /// now.
    ///
    /// Such an activity relaunches Vee moments after the user quits it, and it
    /// lives in launchd rather than in the app, so it survives every update.
    /// Its identifier can only be built from the plugin ID that created it, so
    /// a plugin deleted before this shipped is exactly the case that keeps an
    /// install un-quittable — and exactly the case a per-plugin clear at start
    /// could never reach. Hence the remembered set, and hence running here at
    /// launch rather than from `PluginCoordinator.start()`: the sweep must not
    /// depend on any plugin being installed, enabled, or starting successfully.
    ///
    /// The on-disk listing is unioned in so the first launch after this ships
    /// covers plugins that are present but not yet recorded.
    private func sweepLegacyActivities() {
        let onDisk = PluginDiscovery.enumerate(directory: directory).map(\.id.rawValue)
        prefs.recordSeenPlugins(onDisk)
        LegacyBackgroundActivity.clearAll(pluginIDs: prefs.seenPluginIDs())
    }

    private func startWatching() {
        watcher?.stop()
        watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    /// Reconciles the app item's visibility and the compact item's
    /// app-controls footer against the live "combine everything into one menu
    /// bar item" preference (issue #71 — one icon total, not two side by
    /// side): compact on folds `mainMenu`'s own controls under
    /// `CompactMenuBarController.shared`'s footer and hides its standalone
    /// item; compact off reverses both. Both directions are idempotent — the
    /// underlying calls all no-op on a repeated same-state call — so a
    /// redundant notification can never leak an item or duplicate the footer.
    private func applyCompactMode(_ compact: Bool) {
        mainMenu?.setVisible(!compact)
        guard let mainMenu else { return }
        if compact {
            CompactMenuBarController.shared.installFooter(target: mainMenu)
        } else {
            CompactMenuBarController.shared.removeFooter()
        }
    }

    // MARK: - App-level "bring every window to the front" hotkey

    /// (Re)binds the app-level bring-all-windows hotkey from the stored
    /// combination, recording what actually happened for the General settings
    /// row to show. Deliberately shaped like the per-plugin
    /// `PluginCoordinator.registerHotKey()` — unregister first, so a rebind can
    /// never leave the old combination live, and `nil` from `register` means
    /// another app already owns it.
    ///
    /// Lives here rather than on `DetachedPluginWindows` because the binding is
    /// app-level: it belongs to no plugin, and outlives every window it acts on.
    private func registerFocusWindowsHotKey() {
        if let focusWindowsHotKeyID {
            GlobalHotKeys.shared.unregister(focusWindowsHotKeyID)
            self.focusWindowsHotKeyID = nil
        }
        guard let combo = prefs.focusWindowsHotkey, !combo.isEmpty else {
            focusWindowsHotkeyStatus = .none
            return
        }
        guard let spec = HotKeySpec.parse(combo) else {
            focusWindowsHotkeyStatus = .invalid
            return
        }
        focusWindowsHotKeyID = GlobalHotKeys.shared.register(spec) {
            DetachedPluginWindows.shared.focusAll()
        }
        focusWindowsHotkeyStatus = focusWindowsHotKeyID != nil ? .active(spec.display) : .unavailable(spec.display)
        if focusWindowsHotKeyID == nil {
            log.error("hotkey \(spec.display, privacy: .public) unavailable for bring all windows to front (already in use)")
        }
    }

    /// Persists a combination typed in General settings, rebinds live, and hands
    /// back the resulting status. A hotkey is a live system resource, so it
    /// commits on edit rather than on a Save the Preferences window does not
    /// have; an empty field gives the combination back to the system.
    private func applyFocusWindowsHotkey(_ combo: String) -> HotkeyStatus {
        let trimmed = combo.trimmingCharacters(in: .whitespaces)
        prefs.focusWindowsHotkey = trimmed.isEmpty ? nil : trimmed
        registerFocusWindowsHotKey()
        return focusWindowsHotkeyStatus
    }

    // MARK: - URL scheme (vee:// and swiftbar://)

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { perform(URLActionRouter.routeGated(url)) }
    }

    private func perform(_ action: URLAction) {
        switch action {
        case .refreshAll:
            refreshAll()
        case .refreshPlugin(let name):
            coordinators[name]?.forceRefresh()
        case .enablePlugin(let name):
            setEnabled(true, id: name)
        case .disablePlugin(let name):
            setEnabled(false, id: name)
        case .togglePlugin(let name):
            setEnabled(prefs.isDisabled(name), id: name)
        case .addPlugin(let src):
            installPlugin(from: src)
        case .setEphemeralPlugin(let name, let content, let exitAfter):
            showEphemeral(name: name, content: content, exitAfter: exitAfter)
        case .notify(let title, let subtitle, let body, let href, let pluginID):
            Notifier.post(title: title, subtitle: subtitle, body: body, href: href, pluginID: pluginID)
        case .unknown:
            break
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Also terminates any in-flight refresh's child process, not just the
        // menu-bar item/schedulers — `PluginCoordinator.stop()` cancels its
        // stored refresh Task(s), and `SystemProcessRunner` kills the child
        // on that cancellation (see its `withTaskCancellationHandler`).
        // Otherwise a plugin mid-run at quit would leak past the app's own
        // exit (reparented to launchd, still running).
        coordinators.values.forEach { $0.stop() }
        ephemerals.values.forEach { $0.remove() }
        if let compactModeObserverToken { NotificationCenter.default.removeObserver(compactModeObserverToken) }
        wakeMonitor?.stop()
        watcher?.stop()
        // Symmetry with registerControlRefreshObserver: drop the Darwin observer.
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Largest plugin source Vee will fetch for a `swiftbar://addplugin` install
    /// — a plugin script is a few KB; anything past this is rejected so a hostile
    /// `src` can't stream an unbounded body into memory.
    private static let addPluginSourceCap = 1_000_000

    /// `swiftbar://addplugin?src=…`: download a plugin and install it — but only
    /// after an explicit trust confirmation. A deep link can be opened by any web
    /// page or app, so installing + auto-running a fetched executable without
    /// consent would be unattended code execution; this routes through the same
    /// "see the footprint before it lands" gate the Discover install uses.
    private func installPlugin(from url: URL) {
        // Only fetch over real web schemes — never `file://` (which would read a
        // local file and install it as an executable) or other schemes.
        guard URLScheme.isWebURL(url) else {
            log.error("addplugin rejected non-web src scheme: \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        // Fail closed on a filename we can't sanitize, rather than installing
        // under a fixed fallback name (which would *guarantee* the plugin runs on
        // a default interval).
        guard let filename = try? PluginInstaller.sanitizedFilename(url.lastPathComponent) else {
            log.error("addplugin rejected unusable filename in src")
            return
        }
        let directory = self.directory
        Task { @MainActor in
            do {
                guard let source = try await Self.boundedSource(from: url, cap: Self.addPluginSourceCap),
                      !source.isEmpty else {
                    self.log.error("addplugin fetch empty, oversize, or non-2xx")
                    return
                }
                guard self.confirmInstall(filename: filename, source: source, from: url) else {
                    self.log.info("addplugin cancelled at trust gate")
                    return
                }
                try Self.installFromAddPlugin(filename: filename, source: source, sourceURL: url, into: directory)
                self.reload()
            } catch {
                self.log.error("addplugin failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Writes the provenance record BEFORE the plugin file itself, so there
    /// is never a window where the file is present on disk but untracked —
    /// a bare `swiftbar://addplugin` install used to skip provenance
    /// entirely (IM5/IM12), which let a same-filename reinstall (or a
    /// different store's same-named catalog entry) show a misattributed
    /// trust badge. Provenance is advisory (`try?`): a failure to record it
    /// must never block the actual install. If the file write below throws
    /// instead, the now-orphaned record self-heals — `reload()`'s disk
    /// reconciliation (`reconcileDiskState`) clears any provenance record
    /// with no matching on-disk file on its next run.
    ///
    /// `nonisolated static` (no instance state) and internal (not private) so
    /// this narrow slice — the actual provenance-then-install sequencing —
    /// is unit-testable without the network fetch or the trust-confirmation
    /// `NSAlert` around it in `installPlugin(from:)`.
    nonisolated static func installFromAddPlugin(filename: String, source: String, sourceURL: URL, into directory: String) throws {
        let provenance = PluginProvenance(filename: filename, sourceURL: sourceURL, source: source)
        try? ProvenanceStore(directory: directory).record(provenance)
        try PluginInstaller.install(filename: filename, source: source, into: directory)
    }

    /// Streams a URL body with a hard byte cap, rejecting a non-2xx status or an
    /// oversize response (returns `nil`) rather than buffering it whole.
    private static func boundedSource(from url: URL, cap: Int) async throws -> String? {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > cap { return nil }
        }
        return String(data: data, encoding: .utf8)
    }

    /// Shows the plugin's plain-language capability footprint and requires an
    /// explicit click before an `addplugin` install writes anything to disk.
    private func confirmInstall(filename: String, source: String, from url: URL) -> Bool {
        let summary = TrustAnalyzer.analyze(TrustParser.parse(source: source))
        let warnings = Self.installGateWarnings(source: source)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Install “\(filename)” from the web?"
        var info = "From \(url.host ?? url.absoluteString)\n\nIt will run unsandboxed on a schedule once installed.\n\nWhat it can do:\n"
        if summary.badges.isEmpty {
            info += "• Nothing declared — its footprint is unknown."
        } else {
            info += summary.badges.map { "• \($0.capability.plainName): \($0.detail)" }.joined(separator: "\n")
        }
        if !warnings.isEmpty {
            info += "\n\n" + warnings.map { "⚠︎ \($0)" }.joined(separator: "\n")
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Every warning the install gate must show for `source`.
    ///
    /// The same two sources the Discover gate combines
    /// (`PluginBrowserModel.requestInstall`): what the plugin *declared*, and
    /// what a scan of its source suggests it does but did NOT declare. The
    /// deep-link gate showed only the first, so the install path with the least
    /// context about where a plugin came from was also the one telling the user
    /// the least about what it does.
    ///
    /// `nonisolated static` so this — the actual warning set, the part worth
    /// asserting — is unit-testable without the `NSAlert` around it.
    nonisolated static func installGateWarnings(source: String) -> [String] {
        let declaration = TrustParser.parse(source: source)
        return TrustAnalyzer.analyze(declaration).warnings
            + TrustAnalyzer.installWarnings(declaration: declaration, source: source)
    }

    /// `swiftbar://setephemeralplugin?name=…&content=…&exitafter=N`: show
    /// transient menu content in its own status item, without a file on disk.
    private func showEphemeral(name: String, content: String, exitAfter: TimeInterval?) {
        let key = name.isEmpty ? UUID().uuidString : name
        let controller: StatusItemController
        if let existing = ephemerals[key] {
            controller = existing
        } else {
            controller = StatusItemController(
                pluginName: key,
                // Ephemeral plugins have no file on disk, so there is no
                // plugin context to merge — and their `shell=`/`shortcut=`
                // actions are stripped before render anyway
                // (`strippingShellActions`), so nothing here executes with it.
                handler: AppActionDispatcher(runner: SystemProcessRunner(), environment: { [baseEnvironment] in baseEnvironment }, onRefresh: {}),
                onRefresh: {}
            )
            ephemerals[key] = controller
        }
        // Ephemeral content arrives via a deep link that any web page/app can
        // open, so strip executable (`shell=`/`bash=`) actions: a URL-injected
        // status item must not be able to run arbitrary commands on click.
        // (`href=` is already scheme-filtered at parse.)
        controller.render(Self.strippingShellActions(OutputParser.parse(content)))

        // Cancel any previous deadline for this key unconditionally — even an
        // update with no exitafter (meant to persist) must not be removed by a
        // still-pending timer from an earlier call.
        ephemeralExpiries[key]?.cancel()
        ephemeralExpiries[key] = nil
        if let exitAfter, exitAfter.isFinite, exitAfter > 0 {
            ephemeralExpiries[key] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(exitAfter * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.ephemerals[key]?.remove()
                self.ephemerals[key] = nil
                self.ephemeralExpiries[key] = nil
            }
        }
    }

    /// Returns a copy of a parsed output with every code-executing action
    /// removed (title lines, items, submenus, and alternates). Used to defang
    /// menu content injected through the `setephemeralplugin` deep link.
    ///
    /// `setephemeralplugin` is not in `URLActionRouter.needsConfirmation`, so
    /// any web page can put a row in the menu bar with no prompt — which makes
    /// every action `AppActionDispatcher.perform` can dispatch reachable from
    /// one click on a row the user never installed. `shell=` was stripped from
    /// the start; `shortcut=` (`/usr/bin/shortcuts run <name>`) and `webview=`
    /// (a `WKWebView` with JS enabled and no navigation delegate) are the same
    /// class of thing and are stripped for the same reason.
    nonisolated static func strippingShellActions(_ output: ParsedOutput) -> ParsedOutput {
        var out = output
        out.titleLines = out.titleLines.map { var line = $0; defang(&line.params); return line }
        out.body = out.body.map(stripShell)
        return out
    }

    /// The one place that decides what an untrusted row may not do. Every
    /// caller below routes through it so a title line, an item, an alternate
    /// and a submenu row can never drift apart.
    nonisolated private static func defang(_ params: inout LineParams) {
        params.shell = nil
        params.swiftbar.shortcut = nil
        params.swiftbar.webview = nil
    }

    nonisolated private static func stripShell(_ node: MenuNode) -> MenuNode {
        switch node {
        case .separator:
            return .separator
        case .item(var item):
            defang(&item.params)
            if var alternate = item.alternate {
                defang(&alternate.params)
                item.alternate = alternate
            }
            item.submenu = item.submenu.map(stripShell)
            return .item(item)
        }
    }

    // MARK: - Loading

    private func enabledPlugins() -> [DiscoveredPlugin] {
        PluginDiscovery.enabled(directory: directory).filter { !prefs.isDisabled($0.id.rawValue) }
    }

    /// Reloads the plugin set from disk. Internal (not private) so a test can
    /// drive it directly — the same seam `makeLibraryModel` already is —
    /// without going through `applicationDidFinishLaunching`, which touches
    /// `NSApp` and is unsafe to invoke from a unit test.
    func reload(reconcile: Bool = true) {
        // Runs on EVERY call, unconditionally, before the early-return below:
        // a disabled plugin is excluded from `enabledPlugins()` (and so never
        // enters `signature`), so deleting a *disabled* plugin's file would
        // never change the signature at all — GC gated behind that check
        // would then never fire for it. GC has to look at the full disk
        // listing anyway (see `reconcileDiskState`), independent of which
        // plugins happen to be enabled.
        //
        // `reconcile: false` is for the one caller that changes `directory`
        // out from under it — see `setPluginsDirectory`.
        if reconcile { reconcileDiskState() }

        let plugins = enabledPlugins()
        // Remember every plugin loaded, for the legacy-activity sweep — see
        // `sweepLegacyActivities()`. A plugin's *removal* is the case that
        // sweep exists to survive, so this record is never pruned.
        prefs.recordSeenPlugins(plugins.map(\.id.rawValue))
        let signature = PluginChangeSnapshot.snapshot(plugins)
        // Rebuild when the effective set changes OR any plugin's file changes on
        // disk (by modification time/size). Keying on the path set alone missed
        // an in-place edit (same filename), so header-derived config — schedule,
        // hotkey, runInBash, the trust footprint — silently kept its stale value
        // until a toggle or relaunch. Still coalesced by the directory watcher's
        // debounce, so this doesn't storm on rapid saves.
        if !coordinators.isEmpty, signature == loadedSignature { return }
        loadedSignature = signature

        coordinators.values.forEach { $0.stop() }
        coordinators.removeAll()

        for plugin in plugins {
            let coordinator = PluginCoordinator(plugin: plugin, pluginsDirectory: directory, runtime: runtime, baseEnvironment: baseEnvironment)
            let id = plugin.id.rawValue
            let name = plugin.filename.name
            let interval = plugin.filename.interval.timeInterval
            coordinator.onPublish = { [weak self] publish in
                self?.widgetPublisher.publish(id: id, name: name, interval: interval, publish: publish)
                // Keep an open Plugin Manager's error badge live: push this run's
                // error state (nil on success), or a still-unresolved hotkey
                // collision, into the row. Cheap — setError only mutates when
                // the value actually changed.
                self?.currentManagerModel?.setError(self?.coordinators[id]?.displayError, id: id)
            }
            coordinators[id] = coordinator
            coordinator.start()
        }
        // Drop widget entries for plugins that are no longer loaded.
        widgetPublisher.setLoaded(ids: Set(coordinators.keys))
    }

    /// Garbage-collects every satellite state store — disabled flag, hotkey
    /// prefs, `.vars.json` sidecar, Keychain secret, catalog provenance
    /// record — for a plugin filename that has state but no file on disk.
    /// Every one of those stores is keyed by filename (see `PluginID`), so
    /// without this, a later plugin landing under the SAME filename inherits
    /// a stranger's disabled flag, credential, or provenance record.
    ///
    /// Covers both an in-app delete (`deletePlugin`, which already calls
    /// `reload()` right after trashing — so it GCs for free, immediately,
    /// through this same path) and a manual Finder/`rm` delete (the
    /// directory watcher calls `reload()` on any change, in-app or not).
    ///
    /// Disk-authoritative and conservative by construction — TWO separate
    /// hard guards, because deleting a Keychain secret is irreversible and
    /// "can't confirm absence" must always mean "don't touch it," never
    /// "assume it's gone":
    /// - **A failed/unreadable listing never GCs.** `PluginDiscovery.enumerate`
    ///   silently folds a read failure into `[]` (`try?`), which is
    ///   indistinguishable from "really empty" — so this takes its own raw
    ///   listing instead, purely to keep that failure signal, and bails out
    ///   entirely on a throw (a permissions hiccup, a volume that vanished
    ///   mid-read, …).
    /// - **A successful but EMPTY listing never GCs either — this is NOT the
    ///   same case as above.** A throw and an empty-but-successful result
    ///   both "look like nothing's there", but only a throw is unambiguous.
    ///   An empty success also happens on a plugins directory that lives on
    ///   a not-yet-mounted network/automount volume: `PluginsDirectory
    ///   .ensureExists` `mkdir`s an empty *local* placeholder the instant
    ///   before the real volume mounts over it, and `UserDefaults`-backed
    ///   candidates (`disabledIDs()` etc.) are readable regardless of
    ///   whether the real directory has mounted yet — so without this
    ///   guard, that split-second window would wipe every plugin's disabled
    ///   flag and Keychain secret, then have them silently reappear
    ///   re-enabled once the mount lands. `onDisk` (the raw listing, before
    ///   any plugin-file filtering) is the right thing to test empty: it
    ///   also contains Vee's own dot-prefixed ledgers
    ///   (`.vee-provenance.json`, `.vee-catalog-snapshot.json`, any
    ///   `.vars.json`), so a directory where the user genuinely deleted
    ///   their *last real plugin* — but has ever installed via Discover, set
    ///   a var, or opened Discover once — still reads non-empty and still
    ///   GCs normally. Only a directory that has NEVER had anything written
    ///   to it by Vee or the user skips GC, and only leaks (never wipes)
    ///   that one plugin's state until something else populates the folder
    ///   — safe-but-leaky beats false-wipe here.
    ///
    /// It also only ever acts on a filename it already has independent
    /// evidence for (a stored pref, a `.vars.json` sidecar, a provenance
    /// record, or the `secretPluginIDs()` marker below) — never a blind
    /// Keychain sweep; there is no "list every Vee plugin's Keychain items"
    /// API, and inventing one for an irreversible delete is the wrong shape.
    ///
    /// `PluginInstaller.install` (fresh install AND in-place update alike)
    /// writes atomically (rename over the destination — see its doc
    /// comment), so an update never presents a "file momentarily absent"
    /// window that could trip this into GC-ing a plugin mid-update.
    private func reconcileDiskState() {
        guard let rawNames = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        let onDisk = Set(rawNames)
        // See the guard's own explanation above: a throw and an empty
        // success are different failure shapes, and BOTH must be treated as
        // "can't confirm" — this is not a fallback for the throw case above,
        // it's an independent guard against a different ambiguity.
        guard !onDisk.isEmpty else { return }

        let provenanceStore = ProvenanceStore(directory: directory)
        var candidates = prefs.disabledIDs()
            .union(prefs.hotkeyDisabledIDs())
            .union(prefs.hotkeyBindingIDs())
            .union(prefs.secretPluginIDs())
            .union(provenanceStore.all().keys)
        // `.vars.json` sidecars live on disk next to their plugin but are
        // filtered out of every plugin listing (`PluginDiscovery` skips
        // them), so they have to be hunted for directly by suffix rather
        // than read off `onDisk`/`PluginDiscovery`'s output.
        let sidecarSuffix = ".vars.json"
        candidates.formUnion(rawNames.filter { $0.hasSuffix(sidecarSuffix) }.map { String($0.dropLast(sidecarSuffix.count)) })

        // Claim everything actually in this folder as living here, BEFORE
        // deciding what's gone — so a plugin present right now can never be
        // collected on the strength of a stale home record.
        prefs.recordPluginHomes(onDisk, directory: directory)

        // Anything back on disk is no longer missing; its clock resets.
        missingSince = missingSince.filter { !onDisk.contains($0.key) }
        let now = Date()

        for filename in candidates where !onDisk.contains(filename) {
            // Absent from THIS folder is only evidence of deletion if this
            // folder is where the record came from. A record homed elsewhere
            // belongs to a plugin that is still on disk in a folder Vee isn't
            // looking at — collecting it would destroy a live plugin's
            // Keychain secrets irreversibly (see `AppPreferences.pluginHome`).
            // An unhomed record predates that bookkeeping and stays collectable,
            // which is the behavior every single-folder install already had.
            if let home = prefs.pluginHome(filename), home != directory { continue }

            // One absent listing is not proof of deletion. The directory
            // watcher fires on a 0.3s debounce, so this runs during any moment
            // the file isn't there: a non-atomic editor save (write to a temp
            // file, unlink, rename), a plugin dragged out to edit and dragged
            // back, a network/automount volume between unmount and remount.
            // Destroying Keychain secrets on the strength of one such moment is
            // irreversible, and every one of those cases resolves in seconds.
            // Require the absence to persist instead.
            let firstMissing = missingSince[filename] ?? now
            missingSince[filename] = firstMissing
            guard now.timeIntervalSince(firstMissing) >= deletionGracePeriod else { continue }
            missingSince[filename] = nil

            prefs.clearAllState(id: filename)
            prefs.clearPluginHome(filename)
            VarStore(pluginPath: (directory as NSString).appendingPathComponent(filename)).delete()
            try? provenanceStore.remove(filename: filename)
            secretStoreFactory(PluginID(rawValue: filename)).deleteAll()
        }
    }

    /// Whether `id` currently has a live coordinator — i.e. it passed the
    /// enabled-plugins filter and was loaded by the last `reload()`. Exposed
    /// for tests; production code has no need to enumerate this.
    func isLoaded(id: String) -> Bool { coordinators[id] != nil }

    // MARK: - Control Center refresh

    /// Observes the Darwin notification the control posts, so a refresh fires
    /// immediately when Vee is already running.
    private func registerControlRefreshObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in AppController.shared?.controlRefreshFired() }
            },
            VeeWidgetSharing.refreshRequestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func controlRefreshFired() {
        refreshAll()
    }

    // MARK: - Per-plugin widget actions

    /// Observes the Darwin notification a widget card's action button posts
    /// after writing a `WidgetActionRequest`, so it's serviced immediately
    /// while Vee is already running. Generalizes `registerControlRefreshObserver`
    /// (refresh-all) to a specific plugin id.
    private func registerWidgetActionObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in AppController.shared?.widgetActionRequestFired() }
            },
            VeeWidgetSharing.actionRequestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Reads and clears the pending request (a no-op if none is pending —
    /// this is also called unconditionally once at launch) and services it:
    /// `.refresh` re-runs the plugin *on its widget surface* (so the card the
    /// button lives on actually updates); `.run` resolves `actionIndex` against
    /// the plugin's currently-published card and runs its shortcut.
    func widgetActionRequestFired() {
        guard let request = VeeWidgetSharing.actionRequestStore.readAndClear() else { return }
        switch request.action {
        case .refresh:
            // Widget surface, not menu: the card is produced only by the
            // widget-mode run, and the menu-mode refresh publishes nothing for a
            // `.both`/`.widget` plugin (see `PluginCoordinator.forceRefreshWidget`).
            coordinators[request.pluginID]?.forceRefreshWidget()
        case .run, .runItem:
            runCardAction(for: request)
        }
    }

    /// Resolves a `.run`/`.runItem` request's `actionIndex` against the
    /// plugin's currently-published card and runs the Shortcut it names — a
    /// card action button for `.run`, a tappable `list`/`board` row for
    /// `.runItem`. The two index *different* lists, which is why the request
    /// carries which one it means rather than a bare position.
    ///
    /// Only a Shortcut is ever posted this way (see `WidgetActionRequest`):
    /// a URL is opened by the extension itself. Anything else here — a stale
    /// index, a row that no longer declares a Shortcut — is ignored
    /// defensively; the card is re-read from the snapshot, so it may have moved
    /// on since the tap.
    private func runCardAction(for request: WidgetActionRequest) {
        guard let index = request.actionIndex,
              let card = VeeWidgetSharing.shared.read()?.plugins.first(where: { $0.id == request.pluginID })?.card
        else { return }

        let name: String?
        if request.action == .runItem {
            let items = card.items ?? []
            name = items.indices.contains(index) ? items[index].shortcut : nil
        } else {
            let actions = card.actions ?? []
            name = actions.indices.contains(index) && actions[index].kind == .shortcut ? actions[index].name : nil
        }
        guard let name, !name.isEmpty else { return }
        runShortcut(named: name)
    }

    /// Runs a macOS Shortcut by name via the `shortcuts` CLI — the same
    /// mechanism `AppActionDispatcher.runShortcut` uses for menu `shortcut=`,
    /// duplicated in miniature here since this fires with no live
    /// `PluginCoordinator`/dispatcher in hand (it's dispatched by plugin id
    /// from a request file, not a menu click).
    private func runShortcut(named name: String) {
        let invocation = ProcessInvocation(launchPath: "/usr/bin/shortcuts", arguments: ["run", name], environment: baseEnvironment)
        Task { _ = try? await SystemProcessRunner().run(invocation) }
    }

    // MARK: - Global actions

    /// Spacing between staggered plugin refreshes in a fan-out.
    private static let refreshStaggerStep: TimeInterval = 0.05

    /// Re-runs every plugin, but staggered: firing on wake/launch/control with
    /// many plugins would otherwise spawn N subprocesses at once — a CPU/thread
    /// spike at the worst moment. Each start is offset by a small step (capped so
    /// the spread stays bounded for large plugin sets).
    private func refreshAll() {
        for (index, coordinator) in coordinators.values.enumerated() {
            let delay = Swift.min(Double(index) * Self.refreshStaggerStep, 5.0)
            if delay == 0 {
                coordinator.forceRefresh()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    coordinator.forceRefresh()
                }
            }
        }
    }

    private func openFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: directory)) }

    private func openManager() {
        LibraryWindow.shared.show(model: makeLibraryModel(section: .installed))
    }

    /// Builds the model for the consolidated window (`LibraryView`): the
    /// installed-plugin rows (populated off the main thread) plus the
    /// General/Stores/Variables settings sub-models. Both ⌘M (Installed) and ⌘,
    /// (General) route here, jumping to their section. Internal (not private)
    /// so a test can verify the `.discover`-scoped model `onOpenDiscover`
    /// ultimately shows, without going through `openBrowser()`'s
    /// `LibraryWindow.shared.show` — which touches `NSApp` and is unsafe to
    /// invoke from a unit test.
    func makeLibraryModel(section: LibrarySection) -> LibraryModel {
        let manager = PluginManagerModel(
            rows: [],
            currentDirectory: directory,
            launchAtLogin: LoginItemManager.isEnabled,
            onToggleEnabled: { [weak self] id, enabled in self?.setEnabled(enabled, id: id) },
            onReveal: { [weak self] id in self?.reveal(id) },
            onSettings: { [weak self] id in self?.coordinators[id]?.showSettings() },
            onDebug: { [weak self] id in self?.coordinators[id]?.showDebugConsole() },
            onDelete: { [weak self] id in self?.deletePlugin(id) },
            onDiscover: { [weak self] in self?.openBrowser() },
            onLaunchAtLogin: { enabled in LoginItemManager.setEnabled(enabled) },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() }
        )
        // Held weakly so coordinators can push live error updates into the open
        // window; the window retains the model, so this nils out once it closes.
        currentManagerModel = manager

        // Reading and parsing every plugin's source is the slow part, so build
        // the rows off the main thread and populate the model when ready — the
        // window opens immediately instead of blocking the menu action on a
        // synchronous fan-out of file reads + header/trust parses. Inputs are
        // snapshotted on the main actor first; only the disk read + parse runs
        // detached (every type it touches is Sendable).
        let inputs = managerRowInputs()
        Task { [weak manager] in
            let rows = await Task.detached(priority: .userInitiated) {
                AppController.buildManagerRows(inputs)
            }.value
            manager?.rows = rows
            manager?.isLoaded = true
        }

        let general = GeneralSettingsModel(
            currentDirectory: directory,
            launchAtLogin: LoginItemManager.isEnabled,
            onLaunchAtLogin: { LoginItemManager.setEnabled($0) },
            onChooseFolder: { [weak self] in self?.chooseFolderFromPreferences() },
            onOpenFolder: { [weak self] in self?.openFolder() },
            onRefreshAll: { [weak self] in self?.refreshAll() },
            focusWindowsHotkey: prefs.focusWindowsHotkey ?? "",
            focusWindowsHotkeyStatus: focusWindowsHotkeyStatus,
            onApplyFocusWindowsHotkey: { [weak self] combo in self?.applyFocusWindowsHotkey(combo) ?? .none },
        )
        generalSettingsModel = general

        let groups = VariableAggregator.aggregate(plugins: aggregatablePlugins(), reader: HeaderVariableReader())
        let variables = VariablesEditorModel(groups: groups, onSaved: { [weak self] in self?.refreshAll() })

        let stores = StoresSettingsModel()

        return LibraryModel(
            section: section,
            manager: manager,
            general: general,
            stores: stores,
            variables: variables,
            browser: browserModel(),
            // Resolves an installed plugin id to its live Settings/Debug models
            // for in-pane display — built from the plugin's coordinator without
            // opening a window. `nil` for an unknown id.
            pluginDetail: { [weak self] id in
                guard let coordinator = self?.coordinators[id] else { return nil }
                return PluginDetailModels(
                    settings: coordinator.hasSettings ? coordinator.settingsModel() : nil,
                    debug: coordinator.debugModel()
                )
            }
        )
    }

    /// The retained Discover catalog model, embedded in the consolidated window's
    /// Discover section. Rebuilt only when the store set or plugins directory
    /// changes; otherwise the already-fetched catalog (and per-plugin
    /// header/freshness caches) is reused so Discover opens instantly with no
    /// re-fetch (#56). The view's `.task { if entries.isEmpty }` guard skips a
    /// re-fetch on the reused model, and `isInstalled` reads disk live so the
    /// installed state stays correct. Explicit refresh stays on the toolbar
    /// Refresh button.
    private func browserModel() -> PluginBrowserModel {
        // Discover spans every configured store — the built-in public catalog
        // plus any user-added or MDM-managed enterprise stores.
        let registry = StoreRegistry()
        let stores = registry.stores()

        if let cached = cachedBrowserModel, cachedBrowserStores == stores, cachedBrowserDirectory == directory {
            return cached
        }

        let model = PluginBrowserModel(
            stores: stores,
            makeClient: { store in
                let token: StoreTokenProviding? = store.authMode == .token ? KeychainStoreTokenStore(storeID: store.id) : nil
                return CatalogClientFactory.make(for: store, tokenProvider: token)
            },
            pluginsDirectory: directory,
            onInstalled: { [weak self] in self?.reload() },
            onUpdatesFound: { candidates, installed in
                // Skip the banner while the user is already in the Vee window
                // looking at Discover's own Update buttons — it would only
                // re-open the window they're in. Skipped versions are never
                // marked notified, so the launch-time snapshot scan still
                // surfaces them later. Pruning still runs either way.
                let windowInFront = LibraryWindow.shared.isVisible && (NSApp?.isActive ?? false)
                Notifier.notifyCatalogUpdates(windowInFront ? [] : candidates, installedFilenames: installed)
            }
        )
        cachedBrowserModel = model
        cachedBrowserStores = stores
        cachedBrowserDirectory = directory
        return model
    }

    /// Opens the consolidated window on the Discover section. Kept as a thin
    /// wrapper (rather than inlined) so the ⌘D menu action, the Manager
    /// empty-state, and first-run all route through one place.
    private func openBrowser() {
        LibraryWindow.shared.show(model: makeLibraryModel(section: .discover))
    }

    /// Launch-time catalog-update scan against the on-disk snapshot written by
    /// the last successful Discover load (`CatalogSnapshotStore`) — makes the
    /// update nudge proactive without any network fetch at launch (Vee makes
    /// no unexplained launch network calls; cf. matryer/xbar#859). No snapshot
    /// (never opened Discover) or no catalog-installed plugins → silent no-op.
    private func scanCatalogSnapshotForUpdates() {
        let dir = directory
        Task.detached(priority: .utility) {
            let entries = CatalogSnapshotStore(directory: dir).load()
            guard !entries.isEmpty else { return }
            let installed = Array(ProvenanceStore(directory: dir).all().values)
            guard !installed.isEmpty else { return }
            let freshness = CatalogFreshnessStore(directory: dir)
            let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: entries) {
                freshness.date(for: $0.id) ?? $0.lastUpdated
            }
            let installedNames = Set(installed.map(\.filename))
            await Notifier.notifyCatalogUpdates(candidates, installedFilenames: installedNames)
        }
    }

    /// On the very first launch, a brand-new user sees only a menu-bar icon and
    /// has to guess what to do. If their plugins folder is also empty, open
    /// Discover once so there's an obvious next step. Existing SwiftBar/xbar
    /// users (who already have plugins) are left undisturbed.
    ///
    /// Also seeds `xbar` disabled-by-default (`vee-plugins` is now the
    /// default store) — this MUST run before `prefs.hasCompletedFirstRun` is
    /// set below, since that's exactly the signal `seedDefaultStoresIfNeeded`
    /// uses to tell a fresh install from an existing one.
    private func presentFirstRunIfNeeded() {
        StoreRegistry().seedDefaultStoresIfNeeded()
        guard !prefs.hasCompletedFirstRun else { return }
        prefs.hasCompletedFirstRun = true
        if PluginDiscovery.enumerate(directory: directory).isEmpty {
            openBrowser()
        }
    }

    // MARK: - Preferences

    /// Installs a minimal application main menu. Vee is an `.accessory` app so
    /// this menu is never shown, but its key equivalents (⌘, for Preferences,
    /// and the standard Edit-menu clipboard commands used when pasting API
    /// tokens into the Variables editor) are dispatched to the key window.
    private func installAppMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        prefs.target = self
        appMenu.addItem(prefs)

        let editItem = NSMenuItem()
        editItem.title = "Edit"
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    /// Opens the app-wide Preferences window (⌘,): a General tab reusing the
    /// app-level settings and a Variables tab aggregating every installed
    /// plugin's declared `<xbar.var>` variables.
    @objc private func openPreferences() {
        LibraryWindow.shared.show(model: makeLibraryModel(section: .general))
    }

    /// Every installed plugin, described for the pure variable aggregator.
    private func aggregatablePlugins() -> [AggregatablePlugin] {
        PluginDiscovery.enumerate(directory: directory).map {
            AggregatablePlugin(id: $0.id, name: $0.filename.name, path: $0.path)
        }
    }

    /// Folder chooser invoked from the Preferences General tab; also refreshes
    /// the tab's displayed path so it stays in sync.
    private func chooseFolderFromPreferences() {
        guard let path = promptForPluginsFolder() else { return }
        setPluginsDirectory(path)
        generalSettingsModel?.currentDirectory = path
    }

    /// Prompts for a plugins folder (e.g. an existing SwiftBar folder) and
    /// switches to it.
    private func chooseFolder() {
        guard let path = promptForPluginsFolder() else { return }
        setPluginsDirectory(path)
    }

    /// Runs the open panel and returns the chosen folder path, or `nil` if
    /// cancelled.
    private func promptForPluginsFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directory)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private func setPluginsDirectory(_ path: String) {
        prefs.pluginsDirectory = path
        directory = path
        PluginsDirectory.ensureExists(directory)
        loadedSignature.removeAll()
        // Skips disk reconciliation: switching folders is not evidence that
        // anything was deleted, and the old folder's plugins are all "missing"
        // from the new one by definition. `reconcileDiskState` won't collect
        // them anyway (it is scoped by `AppPreferences.pluginHome`), but the
        // records this reload would GC against belong to a folder Vee was
        // pointed at a moment ago — the safe pass is the one that runs after
        // the new folder has been listed at least once.
        reload(reconcile: false)
        startWatching()
    }

    private func setEnabled(_ enabled: Bool, id: String) {
        prefs.setDisabled(!enabled, id: id)
        reload()
    }

    private func reveal(_ id: String) {
        guard let plugin = PluginDiscovery.enumerate(directory: directory).first(where: { $0.id.rawValue == id }) else { return }
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: directory)
    }

    /// Moves a plugin's script to the Trash (recoverable) and reloads so its
    /// status item and coordinator are torn down. The manager has already removed
    /// the row optimistically. `loadedSignature` is deliberately left untouched:
    /// it's the change-detection baseline reload() compares against, so the
    /// now-deleted path dropping out of the fresh signature guarantees reload()
    /// sees the diff and rebuilds (clearing it here would be redundant).
    ///
    /// Also GCs this filename's satellite state (disabled flag, hotkey prefs,
    /// `.vars.json`, Keychain secret, provenance) immediately, for free: the
    /// `reload()` below runs `reconcileDiskState()` first thing, and the file
    /// is already gone from disk by the time it does (`trashItem` isn't
    /// async) — see `reconcileDiskState`'s doc comment.
    private func deletePlugin(_ id: String) {
        guard let plugin = PluginDiscovery.enumerate(directory: directory).first(where: { $0.id.rawValue == id }) else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: plugin.path), resultingItemURL: nil)
        reload()
    }

    /// A per-plugin snapshot of the main-actor state a row needs (enabled,
    /// hotkey prefs, last error), gathered on the main actor so the heavy disk
    /// read + parse can then run detached. Every field is `Sendable`.
    private struct ManagerRowInput: Sendable {
        let path: String
        let id: String
        let name: String
        let interval: RefreshInterval
        let isDisabled: Bool
        let isHotkeyDisabled: Bool
        let hotkeyBinding: String?
        let lastError: String?
    }

    /// Gathers the row inputs on the main actor (cheap: directory listing +
    /// prefs/coordinator lookups). The expensive per-file read + parse happens
    /// later in `buildManagerRows`, off the main thread.
    private func managerRowInputs() -> [ManagerRowInput] {
        PluginDiscovery.enumerate(directory: directory).map { plugin in
            let id = plugin.id.rawValue
            return ManagerRowInput(
                path: plugin.path,
                id: id,
                name: plugin.filename.name,
                interval: plugin.filename.interval,
                isDisabled: prefs.isDisabled(id),
                isHotkeyDisabled: prefs.isHotkeyDisabled(id),
                hotkeyBinding: prefs.hotkeyBinding(id),
                lastError: coordinators[id]?.displayError
            )
        }
    }

    /// Builds the manager rows from the snapshotted inputs. `nonisolated static`
    /// so it can run off the main actor (`Task.detached`): it reads each
    /// plugin's source and runs the pure header/trust parsers, touching no
    /// actor-isolated state.
    private nonisolated static func buildManagerRows(_ inputs: [ManagerRowInput]) -> [PluginManagerRow] {
        inputs.map { input in
            let source = PluginSource.read(atPath: input.path) ?? ""
            let header = HeaderParser.parse(source: source)
            let level = TrustAnalyzer.analyze(TrustParser.parse(source: source)).level
            // Declared features gate Settings reachability (so a disabled hotkey
            // stays re-enable-able); the indicators reflect the *effective* state.
            let declaredFeatures = PluginFeatures(header: header)
            let effectiveHotkey: String?
            if case .use(let spec) = EffectiveHotkey.resolve(
                declared: header.shortcut,
                userDisabled: input.isHotkeyDisabled,
                customBinding: input.hotkeyBinding
            ) {
                effectiveHotkey = spec.display
            } else {
                effectiveHotkey = nil
            }
            return PluginManagerRow(
                id: input.id,
                name: input.name,
                interval: describe(input.interval),
                trust: describe(level),
                trustLevel: level,
                // `PluginDiscovery.enabled` (what `enabledPlugins()` actually
                // loads) runs a non-executable plugin bash-wrapped, matching
                // SwiftBar — it isn't filtered by the execute bit. The
                // Manager toggle must reflect that reality (IM10): whether
                // it's disabled, not whether it happens to be +x. This
                // doesn't change WHAT runs, only what this row displays.
                isEnabled: !input.isDisabled,
                hasSettings: !header.vars.isEmpty || !declaredFeatures.isEmpty,
                features: PluginFeatures(searchPanel: header.filter, hotkey: effectiveHotkey),
                lastError: input.lastError,
                surface: header.surface
            )
        }
    }

    private nonisolated static func describe(_ interval: RefreshInterval) -> String {
        switch interval {
        case .manual: return "on demand"
        case .milliseconds(let n): return "\(n)ms"
        case .seconds(let n): return "every \(n)s"
        case .minutes(let n): return "every \(n)m"
        case .hours(let n): return "every \(n)h"
        case .days(let n): return "every \(n)d"
        case .cron(let e): return "cron: \(e)"
        }
    }

    private nonisolated static func describe(_ level: TrustLevel) -> String {
        switch level {
        case .declared: return "capabilities declared"
        case .partial: return "capabilities incomplete"
        case .undeclared: return ""
        }
    }
}
