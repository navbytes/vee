import Foundation
import VeeWidgetShared

/// Owns widget-snapshot publishing state and policy: coalesced writes to the
/// shared snapshot file and metered reload requests, so a fast (e.g. `5s`) or
/// streaming plugin can't blow through WidgetKit's reload budget or churn disk
/// once per tick. Extracted from `AppController` so this policy is independently
/// testable; the production effects (writing the file, asking WidgetKit to
/// reload) are injected, so this type itself stays WidgetKit-free.
@MainActor
final class WidgetSnapshotPublisher {
    private let write: (WidgetSnapshot) -> Void
    private let requestReloadEffect: () -> Void
    private let flushCoalesce: TimeInterval
    private let reloadFloor: TimeInterval
    private let timestampFloor: TimeInterval

    /// Latest published title per plugin, mirrored to the shared snapshot file
    /// so the WidgetKit widget can render it. Flushed (coalesced) on change.
    private var snapshotItems: [String: PluginSnapshot] = [:]
    private var snapshotFlushScheduled = false
    /// The currently-loaded plugin ids, as of the last `setLoaded`. A flush drops
    /// any snapshot entry outside this set, so a plugin that's no longer loaded
    /// doesn't linger in the published file.
    private var loadedIDs: Set<String> = []
    /// The content last written (with volatile timestamps normalized away), so an
    /// unchanged flush is a no-op: a plugin re-running with identical output —
    /// same title, color, gauge, error state — must not churn the file or spend a
    /// widget reload.
    private var lastPublishedSignature: [PluginSnapshot] = []
    /// Throttle state for the reload effect — WidgetKit meters reloads against a
    /// per-app budget, so a fast/streaming plugin must not drive one reload per
    /// tick.
    private var lastWidgetReload: Date = .distantPast
    private var widgetReloadPending = false
    /// When the snapshot file was last written, so timestamp-only refreshes (no
    /// content change) don't churn the disk once per tick — see `flush()`.
    private var lastSnapshotWrite: Date = .distantPast

    init(
        write: @escaping (WidgetSnapshot) -> Void,
        requestReload: @escaping () -> Void,
        flushCoalesce: TimeInterval = 0.3,
        reloadFloor: TimeInterval = 300,
        timestampFloor: TimeInterval = 60
    ) {
        self.write = write
        self.requestReloadEffect = requestReload
        self.flushCoalesce = flushCoalesce
        self.reloadFloor = reloadFloor
        self.timestampFloor = timestampFloor
    }

    /// Records a plugin's current widget state and schedules a coalesced flush to
    /// the shared snapshot file so the WidgetKit widget can render it.
    func publish(id: String, name: String, interval: TimeInterval?, publish: WidgetPublish) {
        snapshotItems[id] = PluginSnapshot(
            id: id,
            name: name,
            title: publish.title,
            updated: Date(),
            color: publish.fields.color.map(WidgetSnapshotMapping.snapshotColor),
            symbolName: publish.fields.symbolName,
            symbolColors: WidgetSnapshotMapping.snapshotColors(publish.fields.symbolColors),
            progress: publish.fields.progress,
            sparkline: publish.fields.sparkline,
            isError: publish.isError,
            interval: interval
        )
        guard !snapshotFlushScheduled else { return }
        snapshotFlushScheduled = true
        Task { @MainActor in
            // Coalesce bursts (many plugins refreshing at once) into one write.
            try? await Task.sleep(nanoseconds: UInt64(self.flushCoalesce * 1_000_000_000))
            self.snapshotFlushScheduled = false
            self.flush()
        }
    }

    /// Updates the set of currently-loaded plugin ids (pruning any snapshot entry
    /// for a plugin that's no longer loaded) and flushes. Called at the end of
    /// `AppController.reload()`.
    func setLoaded(ids: Set<String>) {
        loadedIDs = ids
        flush()
    }

    /// Writes the current snapshot (only currently-loaded plugins, name-sorted)
    /// to the shared file — always, so freshness timestamps stay honest — and asks
    /// for a reload only when the visible *content* changed (and never more often
    /// than the reload floor).
    private func flush() {
        snapshotItems = snapshotItems.filter { loadedIDs.contains($0.key) }
        let plugins = snapshotItems.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        // Detect a visible-content change (title, color, gauge, error state) with
        // the per-run `updated` timestamp normalized away, so a plugin re-running
        // with identical output doesn't spend a widget reload.
        let signature = Self.contentSignature(plugins)
        let contentChanged = signature != lastPublishedSignature
        lastPublishedSignature = signature

        // Write on a real content change immediately. Otherwise the write only
        // refreshes the "last ran" timestamps, so throttle those to avoid churning
        // the disk once per tick for a fast/streaming plugin — the freshness floor
        // is minutes, so a ~minute-old timestamp is still honest. A content change
        // additionally spends a (separately throttled) reload.
        let now = Date()
        guard contentChanged || now.timeIntervalSince(lastSnapshotWrite) >= timestampFloor else { return }
        lastSnapshotWrite = now
        write(WidgetSnapshot(plugins: Array(plugins), generated: now))
        if contentChanged { requestReload() }
    }

    /// The change-detection key for a set of snapshots: the same plugins with the
    /// per-run `updated` timestamp zeroed, so re-running a plugin with identical
    /// output compares equal (only a real content change triggers a reload; the
    /// file itself is still rewritten to keep `updated` current).
    private static func contentSignature(_ plugins: [PluginSnapshot]) -> [PluginSnapshot] {
        plugins.map {
            PluginSnapshot(
                id: $0.id, name: $0.name, title: $0.title,
                updated: Date(timeIntervalSince1970: 0),
                color: $0.color, symbolName: $0.symbolName, symbolColors: $0.symbolColors,
                progress: $0.progress, sparkline: $0.sparkline, isError: $0.isError, interval: $0.interval
            )
        }
    }

    /// Asks for a reload, throttled to `reloadFloor`. If a reload happened
    /// recently, one trailing reload is scheduled at the end of the window so the
    /// latest change still lands.
    private func requestReload() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWidgetReload)
        if elapsed >= reloadFloor {
            lastWidgetReload = now
            requestReloadEffect()
        } else if !widgetReloadPending {
            widgetReloadPending = true
            let delay = reloadFloor - elapsed
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self.widgetReloadPending = false
                self.lastWidgetReload = Date()
                self.requestReloadEffect()
            }
        }
    }
}
