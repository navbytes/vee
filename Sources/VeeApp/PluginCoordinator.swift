import AppKit
import Foundation
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeePreferences
import VeeTrust
import VeeUI
import VeeWidgetShared

/// Drives one plugin end-to-end: parses its header, renders it into a status
/// item, runs it on a schedule, and refreshes on demand.
@MainActor
final class PluginCoordinator {
    private let plugin: DiscoveredPlugin
    private let pluginsDirectory: String
    private let runtime: PluginRuntime
    private let baseEnvironment: [String: String]
    private let header: HeaderMetadata
    private let runInBash: Bool
    private let preferences: PluginPreferences

    /// `nil` for a `.widget`-surface plugin: "no NSStatusItem, no menu; invoked
    /// only in widget mode" (see `docs/design/widget-surface-contract.md` §1).
    /// Every other call site null-guards through this. Internal (not
    /// `private`, read-only outside) so `AppController`'s cross-plugin search
    /// aggregator can reach this plugin's live menu/handler — a `.widget`
    /// plugin is excluded naturally since it stays `nil`.
    private(set) var controller: StatusItemController?
    private var timer: RefreshTimer?
    private var background: BackgroundRefreshScheduler?
    private var cron: CronScheduler?
    private var streaming: StreamingSession?
    private var hotKeyID: UInt32?
    private var hotkeyStatus: HotkeyStatus = .none
    private var isRefreshing = false
    /// The second, independent scheduler for `.both`/`.widget` plugins — see
    /// `start()`. Always `BackgroundRefreshScheduler` since the widget cadence
    /// is floored at 5 minutes regardless of source, squarely in that
    /// scheduler's energy-batched range.
    private var widgetBackground: BackgroundRefreshScheduler?
    private var isRefreshingWidget = false
    /// Set by `stop()`. A queued timer/cron/hotkey `refresh()` that fires after
    /// `stop()` must not spawn a subprocess or render into a removed status item.
    private var stopped = false
    private var lastResult: PluginRunResult?
    /// The live debug console model, created lazily on first use and reused
    /// thereafter so both the pop-out window and the in-pane console share one
    /// live-updating instance. Renamed from `debugModel` to free that name for
    /// the `debugModel()` accessor the consolidated window calls.
    private var cachedDebugModel: PluginDebugModel?

    /// The most recent run's error message, or `nil` if the last run succeeded.
    /// The Plugin Manager reads this to flag broken plugins.
    private(set) var lastError: String?

    /// Called with the plugin's current widget state after each render (or an
    /// error marker), so `AppController` can publish it to the widget snapshot.
    /// Set by the owner after init.
    var onPublish: ((WidgetPublish) -> Void)?

    init(plugin: DiscoveredPlugin, pluginsDirectory: String, runtime: PluginRuntime, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.plugin = plugin
        self.pluginsDirectory = pluginsDirectory
        self.runtime = runtime
        self.baseEnvironment = baseEnvironment

        let source = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
        self.header = HeaderParser.parse(source: source)
        // Honor an explicit runInBash; otherwise run executables directly (so a
        // Python/Ruby plugin uses its shebang) and bash-wrap non-executables.
        self.runInBash = header.runInBash ?? !plugin.isExecutable
        self.preferences = PluginPreferences(pluginPath: plugin.path, pluginID: plugin.id, declarations: header.vars)

        let trustSummary = TrustAnalyzer.analyze(TrustParser.parse(source: source))

        let (aboutText, aboutURL) = Self.about(from: header)

        let features = PluginFeatures(header: header)
        // A `.widget`-surface plugin has no menu presence at all — see
        // `docs/design/widget-surface-contract.md` §1. `.menu`/`.both` (the
        // default) get a status item exactly as before.
        if header.surface == .widget {
            self.controller = nil
        } else {
            self.controller = StatusItemController(
                pluginName: plugin.filename.name,
                handler: AppActionDispatcher(runner: SystemProcessRunner(), baseEnvironment: baseEnvironment) { [weak self] in self?.refresh() },
                hasSettings: !header.vars.isEmpty || !features.isEmpty,
                trustSummary: trustSummary,
                refreshOnOpen: header.refreshOnOpen ?? false,
                hideLastUpdated: header.hideLastUpdated,
                filterEnabled: header.filter,
                features: features,
                autosaveName: "com.vee.plugin.\(plugin.id.rawValue)",
                aboutText: aboutText,
                aboutURL: aboutURL,
                onRefresh: { [weak self] in self?.refresh() },
                onSettings: { [weak self] in self?.openSettings() },
                onReveal: { [weak self] in self?.revealInFinder() },
                onEdit: { [weak self] in self?.openInEditor() },
                onDebug: { [weak self] in self?.showDebug() }
            )
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: pluginsDirectory)
    }

    private func openInEditor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: plugin.path))
    }

    /// Builds the About-panel text from header metadata, unless the plugin sets
    /// `<swiftbar.hideAbout>`.
    private static func about(from header: HeaderMetadata) -> (text: String?, url: URL?) {
        guard !header.hideAbout else { return (nil, nil) }
        var lines: [String] = []
        if let version = header.version { lines.append("Version \(version)") }
        if let author = header.author { lines.append("By \(author)") }
        if let summary = header.summary { lines.append(summary) }
        let text = lines.isEmpty ? nil : lines.joined(separator: "\n")
        // Only show an About item when there's something to show.
        return (header.aboutURL == nil && text == nil) ? (nil, nil) : (text, header.aboutURL)
    }

    var pluginID: String { plugin.id.rawValue }

    func forceRefresh() { refresh() }

    /// Re-runs the plugin on its *widget* surface (`VEE_TARGET=widget`) and
    /// republishes the card — what a card's `refresh` action button needs.
    /// Distinct from `forceRefresh()` (the menu surface): for a `.both`/`.widget`
    /// plugin the card is produced only by `refreshWidget()`, and the menu-mode
    /// `refresh()` publishes nothing for it (`publishScrape` is `.menu`-gated),
    /// so routing the button through `forceRefresh()` would leave the card stale
    /// until the next widget-cadence tick. Only ever invoked for plugins that
    /// have a card (i.e. `.both`/`.widget`); a `.menu` plugin never renders an
    /// action button.
    func forceRefreshWidget() { refreshWidget() }

    func showSettings() { openSettings() }

    /// Opens this plugin's debug console (wired to the notification "Open Log" action).
    func showDebugConsole() { showDebug() }

    /// Whether the plugin has anything to configure — declared `<xbar.var>`s or
    /// Vee-native features (search panel / hotkey). Mirrors the `hasSettings`
    /// gate the Manager row computes, so the consolidated window can decide
    /// whether to show a Settings tab at all.
    var hasSettings: Bool {
        !header.vars.isEmpty || !PluginFeatures(header: header).isEmpty
    }

    /// Builds this plugin's settings model — the *single* construction path,
    /// shared by `openSettings()` (pop-out window) and the consolidated window's
    /// in-pane Settings tab. Building it does not open a window.
    func settingsModel() -> PluginSettingsModel {
        let id = plugin.id.rawValue
        return PluginSettingsModel(
            pluginName: plugin.filename.name,
            prefs: preferences,
            features: PluginFeatures(header: header),
            hotkeyControllable: hotkeyControllable,
            hotkeyEnabled: !AppPreferences.shared.isHotkeyDisabled(id),
            hotkeyCombo: AppPreferences.shared.hotkeyBinding(id) ?? header.shortcut?.display ?? "",
            hotkeyStatus: hotkeyStatus,
            onApplyHotkey: { [weak self] enabled, combo in self?.applyHotkey(enabled: enabled, combo: combo) ?? .none },
            onSaved: { [weak self] in self?.refresh() }
        )
    }

    /// Returns this plugin's live debug console model (the cached instance,
    /// created on first use), populated with the last run. The same model the
    /// pop-out window shows, so the in-pane console updates live too.
    func debugModel() -> PluginDebugModel {
        let model = cachedDebugModel ?? PluginDebugModel(pluginName: plugin.filename.name) { [weak self] in self?.refresh() }
        cachedDebugModel = model
        updateDebugModel()
        return model
    }

    private func openSettings() {
        SettingsWindowManager.shared.show(pluginID: plugin.id.rawValue, model: settingsModel())
    }

    func start() {
        registerHotKey()
        // `.widget` has no menu presence — skip the menu-mode run/schedule
        // entirely; only the widget-mode cadence below applies to it.
        if header.surface != .widget {
            if header.streamable {
                startStreaming()
            } else if !header.schedule.isEmpty {
                refresh()
                startCron()
            } else {
                refresh()
                scheduleTimer()
            }
        }
        // `.both`/`.widget` also (or only) run on their own widget-mode cadence.
        if header.surface == .both || header.surface == .widget {
            refreshWidget()
            scheduleWidgetTimer()
        }
    }

    /// Whether the plugin declares a hotkey — i.e. whether it's user-controllable.
    private var hotkeyControllable: Bool { header.shortcut != nil }

    /// The hotkey to actually register, honoring the user's per-plugin override:
    /// off → nil; a custom binding (parsed) → that; otherwise the declared one.
    /// Returns `.some(nil)` intent as distinct states via `hotkeyStatus`.
    private func registerHotKey() {
        if let hotKeyID { GlobalHotKeys.shared.unregister(hotKeyID); self.hotKeyID = nil }

        let id = plugin.id.rawValue
        switch EffectiveHotkey.resolve(
            declared: header.shortcut,
            userDisabled: AppPreferences.shared.isHotkeyDisabled(id),
            customBinding: AppPreferences.shared.hotkeyBinding(id)
        ) {
        case .none:
            hotkeyStatus = .none
        case .disabled:
            hotkeyStatus = .disabled
        case .invalid:
            hotkeyStatus = .invalid
        case .use(let spec):
            hotKeyID = GlobalHotKeys.shared.register(spec) { [weak self] in self?.controller?.openSearchPanel() }
            hotkeyStatus = hotKeyID != nil ? .active(spec.display) : .unavailable(spec.display)
            if hotKeyID == nil {
                VeeLog.make("hotkey").error("hotkey \(spec.display, privacy: .public) unavailable for \(self.plugin.filename.name, privacy: .public) (already in use)")
            }
        }
        updateHotkeyFeature()
    }

    /// Persists a hotkey change from Settings, re-registers live, and returns the
    /// new status for immediate feedback. `enabled=false` turns it off; a `combo`
    /// differing from the declared binding is stored as a custom override.
    private func applyHotkey(enabled: Bool, combo: String) -> HotkeyStatus {
        let id = plugin.id.rawValue
        AppPreferences.shared.setHotkeyDisabled(!enabled, id: id)
        let declared = header.shortcut?.display
        let trimmed = combo.trimmingCharacters(in: .whitespaces)
        AppPreferences.shared.setHotkeyBinding((trimmed.isEmpty || trimmed == declared) ? nil : trimmed, id: id)
        registerHotKey()
        return hotkeyStatus
    }

    /// Reflects the *effective* hotkey (only shown when actually active) in the
    /// menu's Features row, so disabling it removes it from the capabilities view.
    private func updateHotkeyFeature() {
        let activeDisplay: String? = { if case .active(let d) = hotkeyStatus { return d } else { return nil } }()
        controller?.setFeatures(PluginFeatures(searchPanel: header.filter, hotkey: activeDisplay))
    }

    func stop() {
        stopped = true
        if let hotKeyID { GlobalHotKeys.shared.unregister(hotKeyID) }
        hotKeyID = nil
        timer?.stop()
        timer = nil
        background?.stop()
        background = nil
        cron?.stop()
        cron = nil
        streaming?.stop()
        streaming = nil
        widgetBackground?.stop()
        widgetBackground = nil
        controller?.remove()
    }

    /// The plugin's current menu-bar text for the widget snapshot: the first
    /// title line, trimmed. Empty when the plugin printed no title (e.g. an
    /// icon-only item), which the widget renders as a neutral dot.
    static func publishableTitle(_ output: ParsedOutput) -> String {
        (output.titleLines.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The presentation the widget snapshot carries alongside the title: color,
    /// SF Symbol, and a headline gauge/sparkline. Colors and the symbol come from
    /// the title line; a `progress=`/`sparkline=` may instead sit on the first
    /// dropdown item (the common "headline row is the gauge" idiom), so we fall
    /// back to it. Pure (no actor state) so it is `nonisolated` and unit-testable
    /// from an ordinary, non-`@MainActor` test.
    nonisolated static func widgetFields(from output: ParsedOutput) -> WidgetTitleFields {
        var fields = WidgetTitleFields()
        let title = output.titleLines.first
        let titleParams = title?.params
        fields.color = titleParams?.color ?? title?.ansiRuns.first?.foreground
        fields.symbolName = titleParams?.swiftbar.sfimage
        fields.symbolColors = titleParams?.swiftbar.sfcolor
        let firstItemParams = firstBodyItemParams(output.body)
        fields.progress = titleParams?.progress?.fraction ?? firstItemParams?.progress?.fraction
        fields.sparkline = titleParams?.sparkline ?? firstItemParams?.sparkline
        return fields
    }

    /// The params of the first real dropdown item (skipping separators).
    nonisolated private static func firstBodyItemParams(_ body: [MenuNode]) -> LineParams? {
        for node in body {
            if case .item(let item) = node { return item.params }
        }
        return nil
    }

    /// A human-friendly one-line error for a failed run — detects a missing
    /// command (the most common cause) rather than dumping raw stderr.
    static func friendlyError(_ outcome: ProcessOutcome) -> String {
        if let missing = missingCommand(inStderr: outcome.standardError) {
            return "Failed — “\(missing)” not found. Is it installed?"
        }
        let firstLine = outcome.standardError.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Exited with code \(outcome.exitCode)" : "Exited \(outcome.exitCode): \(firstLine)"
    }

    /// Extracts the missing command/binary from common shell error lines. Real
    /// bash output is `"<script>: line N: <cmd>: command not found"`, so the
    /// command is the last colon-field *before* the marker — not the first field
    /// (which is the script path).
    static func missingCommand(inStderr stderr: String) -> String? {
        func lastField(before marker: Range<String.Index>, in line: String) -> String? {
            line[line.startIndex..<marker.lowerBound]
                .split(separator: ":")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last(where: { !$0.isEmpty })
        }
        func firstField(after marker: Range<String.Index>, in line: String) -> String? {
            line[marker.upperBound...]
                .split(separator: ":")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty })
        }

        for raw in stderr.split(separator: "\n") {
            let line = String(raw)
            if let marker = line.range(of: "command not found") {
                // bash: "… : jq: command not found". zsh: "command not found: jq".
                if let cmd = lastField(before: marker, in: line) { return cmd }
                if let cmd = firstField(after: marker, in: line) { return cmd }
            }
            if let marker = line.range(of: "No such file or directory"),
               let path = lastField(before: marker, in: line) {
                return (path as NSString).lastPathComponent
            }
        }
        return nil
    }

    /// Declared preferences merged over `<swiftbar.environment>` values (a
    /// declared `<xbar.var>` wins over a static environment value of the same name).
    private func mergedDeclaredVariables() -> [String: String] {
        header.environment.merging(preferences.environmentValues()) { _, pref in pref }
    }

    /// Schedules refreshes from `<swiftbar.schedule>` cron expressions.
    private func startCron() {
        cron = CronScheduler(schedules: header.schedule) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        cron?.start()
    }

    private func startStreaming() {
        let context = PluginsDirectory.context(pluginPath: plugin.path, pluginsDirectory: pluginsDirectory, declaredVariables: mergedDeclaredVariables())
        let environment = EnvironmentBuilder.merged(base: baseEnvironment, context: context)
        let (launchPath, arguments) = PluginExecutor.launchCommand(pluginPath: plugin.path, runInBash: runInBash)
        let invocation = ProcessInvocation(
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: (plugin.path as NSString).deletingLastPathComponent,
            timeout: nil // streaming plugins run indefinitely
        )
        let session = StreamingSession(
            runner: SystemStreamingRunner(),
            makeInvocation: { invocation },
            onUpdate: { [weak self] output in
                self?.controller?.render(output)
                self?.publishScrape(WidgetPublish(title: Self.publishableTitle(output), fields: Self.widgetFields(from: output)))
            },
            onStopped: { [weak self] message in
                self?.controller?.renderError(message)
                self?.publishScrape(WidgetPublish(title: "⚠︎ stopped", isError: true))
            }
        )
        streaming = session
        session.start()
    }

    private func scheduleTimer() {
        guard let interval = plugin.filename.interval.timeInterval else { return }
        switch RefreshScheduler.strategy(for: plugin.filename.interval) {
        case .highResolutionTimer(let leeway):
            let timer = RefreshTimer()
            timer.start(interval: interval, leeway: leeway) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
            self.timer = timer
        case .backgroundActivity:
            // Long intervals: let the OS batch wake-ups for energy efficiency.
            let scheduler = BackgroundRefreshScheduler(identifier: "com.vee.refresh.\(plugin.id.rawValue)", interval: interval) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
            scheduler.start()
            self.background = scheduler
        case .none:
            return
        }
    }

    private func refresh() {
        // An already-queued timer/cron/hotkey refresh must not run after stop()
        // — the status item is gone, so there's nothing to render into.
        guard !stopped else { return }

        // A streaming script never exits, so running it through the one-shot
        // path below would spawn a duplicate 30s instance that eventually times
        // out and clobbers the live streaming menu with an error. Restart the
        // stream instead. This is silent — StreamingSession.stop() only cancels
        // the run loop's task; it does not invoke onStopped (which would flash
        // an error render).
        if header.streamable {
            streaming?.stop()
            startStreaming()
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true
        controller?.setRefreshing(true)

        let context = PluginsDirectory.context(pluginPath: plugin.path, pluginsDirectory: pluginsDirectory, declaredVariables: mergedDeclaredVariables())
        let runtime = self.runtime
        let path = plugin.path
        let header = self.header
        let runInBash = self.runInBash

        Task { @MainActor [weak self] in
            defer {
                self?.isRefreshing = false
                self?.controller?.setRefreshing(false)
            }
            do {
                // No explicit timeout override here: `runtime.refresh` derives it
                // from `header`'s `<vee.timeout>` (falling back to the default)
                // now that `header` carries the plugin's declared value.
                let result = try await runtime.refresh(pluginPath: path, context: context, header: header, runInBash: runInBash)
                self?.lastResult = result
                self?.updateDebugModel()
                // stop() may have run while this refresh was in flight — a
                // now-removed status item must not be rendered/published into.
                guard self?.stopped != true else { return }
                if result.outcome.timedOut {
                    // Surface whatever the plugin printed before it was killed, so
                    // a hang is debuggable from the menu instead of a dead end.
                    let partial = result.outcome.standardError.isEmpty
                        ? result.outcome.standardOutput
                        : result.outcome.standardError
                    let detail = partial.isEmpty ? nil : String(partial.prefix(500))
                    self?.lastError = "Plugin timed out"
                    self?.controller?.renderError("Plugin timed out", detail: detail)
                    self?.publishScrape(WidgetPublish(title: "⚠︎ timed out", isError: true))
                } else if result.outcome.exitCode != 0 && result.output.titleLines.isEmpty {
                    self?.lastError = Self.friendlyError(result.outcome)
                    self?.controller?.renderError(
                        Self.friendlyError(result.outcome),
                        detail: result.outcome.standardError.isEmpty ? nil : String(result.outcome.standardError.prefix(500))
                    )
                    self?.publishScrape(WidgetPublish(title: "⚠︎ error", isError: true))
                } else {
                    self?.lastError = nil
                    self?.controller?.render(result.output)
                    self?.publishScrape(WidgetPublish(title: Self.publishableTitle(result.output), fields: Self.widgetFields(from: result.output)))
                }
            } catch {
                guard self?.stopped != true else { return }
                self?.lastError = "\(error)"
                self?.controller?.renderError("\(error)")
                self?.publishScrape(WidgetPublish(title: "⚠︎ error", isError: true))
            }
        }
    }

    /// Routes a Tier-0 scrape publish. The scrape only owns the widget
    /// snapshot for a plain `.menu` plugin; for `.both`/`.widget`,
    /// `refreshWidget()` owns it exclusively, so the frequent menu-mode scrape
    /// must not clobber the rich card (a `.both` plugin's menu cadence — e.g.
    /// 5s — fires far more often than its ≥5min widget cadence, so an ungated
    /// scrape would overwrite the card within one tick and churn the reload
    /// budget flip-flopping). Menu rendering (`controller?.render*`) is
    /// unaffected — only the widget publish is gated.
    private func publishScrape(_ publish: WidgetPublish) {
        guard header.surface == .menu else { return }
        onPublish?(publish)
    }

    // MARK: - Widget-mode cadence (`.both`/`.widget` surfaces)

    /// A small safety floor (10s) on the widget-mode re-run cadence — just
    /// enough to stop a pathologically fast filename (e.g. `1s`) from pegging
    /// the CPU in widget mode. It is *not* the old WidgetKit "reload budget"
    /// floor: Vee is an always-running companion app that pushes reloads via
    /// `WidgetCenter` on each data change (see `WidgetSnapshotPublisher` and
    /// `AppController.reloadAllTimelines`), so the widget can track near-real-
    /// time data — the passive ~40–70/day budget applies only to widgets whose
    /// app isn't running.
    static let widgetRefreshFloor: TimeInterval = 10

    /// The widget-mode refresh cadence. Reuses the *same* field the menu bar
    /// does — the plugin's filename interval — with no widget-specific tag,
    /// floored only at the small safety floor: `max(filename interval, floor)`.
    /// A widget-only plugin whose filename carries no interval falls back to
    /// the floor.
    private var widgetRefreshInterval: TimeInterval {
        max(plugin.filename.interval.timeInterval ?? Self.widgetRefreshFloor, Self.widgetRefreshFloor)
    }

    private func scheduleWidgetTimer() {
        let scheduler = BackgroundRefreshScheduler(
            identifier: "com.vee.refresh.widget.\(plugin.id.rawValue)",
            interval: widgetRefreshInterval
        ) { [weak self] in
            Task { @MainActor in self?.refreshWidget() }
        }
        scheduler.start()
        self.widgetBackground = scheduler
    }

    /// Runs the plugin with `VEE_TARGET=widget`, parses stdout as a card, and
    /// publishes it. A plugin that ignores the target and prints menu text
    /// instead degrades gracefully to the Tier-0 scrape of that text (same
    /// `publishableTitle`/`widgetFields` the `.menu` path uses).
    private func refreshWidget() {
        guard !stopped else { return }
        guard !isRefreshingWidget else { return }
        isRefreshingWidget = true

        let context = PluginsDirectory.context(
            pluginPath: plugin.path, pluginsDirectory: pluginsDirectory,
            declaredVariables: mergedDeclaredVariables(), target: .widget
        )
        let runtime = self.runtime
        let path = plugin.path
        let header = self.header
        let runInBash = self.runInBash

        Task { @MainActor [weak self] in
            defer { self?.isRefreshingWidget = false }
            do {
                // No explicit timeout override here: `runtime.refresh` derives it
                // from `header`'s `<vee.timeout>` (falling back to the default)
                // now that `header` carries the plugin's declared value.
                let result = try await runtime.refresh(pluginPath: path, context: context, header: header, runInBash: runInBash)
                guard self?.stopped != true else { return }
                if result.outcome.timedOut {
                    self?.onPublish?(WidgetPublish(title: "⚠︎ timed out", isError: true))
                    return
                }
                let (card, diagnostics) = WidgetCardParser.parse(result.outcome.standardOutput)
                if let card {
                    self?.onPublish?(WidgetPublish(title: card.value ?? card.title ?? "", isError: card.status == .error, card: card))
                } else {
                    // Misbehaving `.both`/`.widget` plugin that never emits a
                    // card: fall back to the Tier-0 scrape (open question #2 in
                    // the design doc) and log the diagnostic rather than
                    // silently dropping it.
                    if !diagnostics.isEmpty {
                        VeeLog.make("widget").warning("\(self?.plugin.filename.name ?? "?", privacy: .public) widget-mode output: \(diagnostics.map(\.message).joined(separator: "; "), privacy: .public)")
                    }
                    self?.onPublish?(WidgetPublish(title: Self.publishableTitle(result.output), fields: Self.widgetFields(from: result.output)))
                }
            } catch {
                guard self?.stopped != true else { return }
                self?.onPublish?(WidgetPublish(title: "⚠︎ error", isError: true))
            }
        }
    }

    // MARK: - Debug console

    private func showDebug() {
        DebugWindowManager.shared.show(pluginID: plugin.id.rawValue, model: debugModel())
    }

    /// Pushes the last run's raw output/diagnostics into the debug console when
    /// it's open.
    private func updateDebugModel() {
        guard let model = cachedDebugModel, let result = lastResult else { return }
        model.update(
            stdout: result.outcome.standardOutput,
            stderr: result.outcome.standardError,
            exitCode: result.outcome.exitCode,
            timedOut: result.outcome.timedOut,
            diagnostics: result.output.diagnostics.map(Self.describe)
        )
    }

    private static func describe(_ diagnostic: ParseDiagnostic) -> String {
        let severity = diagnostic.severity == .error ? "error" : "warning"
        if let line = diagnostic.line {
            return "[\(severity)] line \(line): \(diagnostic.message)"
        }
        return "[\(severity)] \(diagnostic.message)"
    }
}
