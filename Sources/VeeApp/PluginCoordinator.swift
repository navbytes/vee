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
    private let header: HeaderMetadata
    private let runInBash: Bool
    private let preferences: PluginPreferences

    private var controller: StatusItemController!
    private var timer: RefreshTimer?
    private var streaming: StreamingSession?
    private var isRefreshing = false

    init(plugin: DiscoveredPlugin, pluginsDirectory: String, runtime: PluginRuntime) {
        self.plugin = plugin
        self.pluginsDirectory = pluginsDirectory
        self.runtime = runtime

        let source = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
        self.header = HeaderParser.parse(source: source)
        // Honor an explicit runInBash; otherwise run executables directly (so a
        // Python/Ruby plugin uses its shebang) and bash-wrap non-executables.
        self.runInBash = header.runInBash ?? !plugin.isExecutable
        self.preferences = PluginPreferences(pluginPath: plugin.path, pluginID: plugin.id, declarations: header.vars)

        let trustSummary = TrustAnalyzer.analyze(TrustParser.parse(source: source))

        self.controller = StatusItemController(
            pluginName: plugin.filename.name,
            handler: AppActionDispatcher(runner: SystemProcessRunner()) { [weak self] in self?.refresh() },
            hasSettings: !header.vars.isEmpty,
            trustSummary: trustSummary,
            onRefresh: { [weak self] in self?.refresh() },
            onSettings: { [weak self] in self?.openSettings() }
        )
    }

    private func openSettings() {
        let model = PluginSettingsModel(pluginName: plugin.filename.name, prefs: preferences) { [weak self] in
            self?.refresh()
        }
        SettingsWindowManager.shared.show(pluginID: plugin.id.rawValue, model: model)
    }

    func start() {
        if header.streamable {
            startStreaming()
        } else {
            refresh()
            scheduleTimer()
        }
    }

    func stop() {
        timer?.stop()
        timer = nil
        streaming?.stop()
        streaming = nil
        controller.remove()
    }

    private func startStreaming() {
        let context = PluginsDirectory.context(pluginPath: plugin.path, pluginsDirectory: pluginsDirectory, declaredVariables: preferences.environmentValues())
        let environment = EnvironmentBuilder.merged(base: ProcessInfo.processInfo.environment, context: context)
        let invocation = ProcessInvocation(
            launchPath: runInBash ? "/bin/bash" : plugin.path,
            arguments: runInBash ? [plugin.path] : [],
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
        let leeway: TimeInterval
        switch RefreshScheduler.strategy(for: plugin.filename.interval) {
        case .highResolutionTimer(let l):
            leeway = l
        case .backgroundActivity:
            // Long intervals: a leeway-heavy timer suffices for Stage 3;
            // NSBackgroundActivityScheduler wiring can replace this later.
            leeway = interval * 0.2
        case .none:
            return
        }
        let timer = RefreshTimer()
        timer.start(interval: interval, leeway: leeway) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let context = PluginsDirectory.context(pluginPath: plugin.path, pluginsDirectory: pluginsDirectory, declaredVariables: preferences.environmentValues())
        let runtime = self.runtime
        let path = plugin.path
        let header = self.header
        let runInBash = self.runInBash

        Task { @MainActor [weak self] in
            defer { self?.isRefreshing = false }
            do {
                let result = try await runtime.refresh(pluginPath: path, context: context, header: header, runInBash: runInBash, timeout: 30)
                if result.outcome.timedOut {
                    self?.controller.renderError("Plugin timed out")
                } else if result.outcome.exitCode != 0 && result.output.titleLines.isEmpty {
                    self?.controller.renderError("Exited \(result.outcome.exitCode): \(result.outcome.standardError.prefix(200))")
                } else {
                    self?.controller.render(result.output)
                }
            } catch {
                self?.controller.renderError("\(error)")
            }
        }
    }
}
