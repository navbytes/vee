import AppKit
import Foundation
import VeeCore
import VeePluginFormat
import VeeRuntime
import VeePreferences
import VeeTrust
import VeeUI

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

    private var controller: StatusItemController!
    private var timer: RefreshTimer?
    private var background: BackgroundRefreshScheduler?
    private var cron: CronScheduler?
    private var streaming: StreamingSession?
    private var isRefreshing = false

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

        self.controller = StatusItemController(
            pluginName: plugin.filename.name,
            handler: AppActionDispatcher(runner: SystemProcessRunner(), baseEnvironment: baseEnvironment) { [weak self] in self?.refresh() },
            hasSettings: !header.vars.isEmpty,
            trustSummary: trustSummary,
            refreshOnOpen: header.refreshOnOpen ?? false,
            hideLastUpdated: header.hideLastUpdated,
            aboutText: aboutText,
            aboutURL: aboutURL,
            onRefresh: { [weak self] in self?.refresh() },
            onSettings: { [weak self] in self?.openSettings() },
            onReveal: { [weak self] in self?.revealInFinder() },
            onEdit: { [weak self] in self?.openInEditor() }
        )
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

    func showSettings() { openSettings() }

    private func openSettings() {
        let model = PluginSettingsModel(pluginName: plugin.filename.name, prefs: preferences) { [weak self] in
            self?.refresh()
        }
        SettingsWindowManager.shared.show(pluginID: plugin.id.rawValue, model: model)
    }

    func start() {
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

    func stop() {
        timer?.stop()
        timer = nil
        background?.stop()
        background = nil
        cron?.stop()
        cron = nil
        streaming?.stop()
        streaming = nil
        controller.remove()
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

    /// Extracts the missing command/binary from common shell error lines.
    static func missingCommand(inStderr stderr: String) -> String? {
        for raw in stderr.split(separator: "\n") {
            let line = String(raw)
            if line.contains("command not found"), let name = line.split(separator: ":").first {
                return String(name).trimmingCharacters(in: .whitespaces)
            }
            if line.contains("No such file or directory"), let path = line.split(separator: ":").first {
                return (String(path) as NSString).lastPathComponent
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
            onUpdate: { [weak self] output in self?.controller.render(output) },
            onStopped: { [weak self] message in self?.controller.renderError(message) }
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
        guard !isRefreshing else { return }
        isRefreshing = true

        let context = PluginsDirectory.context(pluginPath: plugin.path, pluginsDirectory: pluginsDirectory, declaredVariables: mergedDeclaredVariables())
        let runtime = self.runtime
        let path = plugin.path
        let header = self.header
        let runInBash = self.runInBash

        Task { @MainActor [weak self] in
            defer { self?.isRefreshing = false }
            do {
                let result = try await runtime.refresh(pluginPath: path, context: context, header: header, runInBash: runInBash, timeout: 30)
                if result.outcome.timedOut {
                    self?.controller.renderError("Plugin timed out", detail: nil)
                } else if result.outcome.exitCode != 0 && result.output.titleLines.isEmpty {
                    self?.controller.renderError(
                        Self.friendlyError(result.outcome),
                        detail: result.outcome.standardError.isEmpty ? nil : String(result.outcome.standardError.prefix(500))
                    )
                } else {
                    self?.controller.render(result.output)
                }
            } catch {
                self?.controller.renderError("\(error)")
            }
        }
    }
}
