import AppKit
import Foundation
import VeeProtocol
import VeeEngine
import VeeServices
import VeeKeychain
import VeeApp

// App-side adapters that bridge the running app's real services onto the
// VeeEngine provider protocols the `PluginHost` consumes. The engine ships
// default-deny / empty defaults and a couple of "thin real" impls
// (`NSWorkspaceOpenProvider`, `FileManagerFileProvider`, `DiskStorageBackend`,
// `KeychainStore`); these types fill the two seams that need to be backed by
// LIVE app state — the clipboard-history monitor and EventKit — plus the small
// keychain→`TokenStoring` adapter the Settings window needs.
//
// All of this lives in the executable target (not a library) because it stitches
// VeeServices' running objects to VeeEngine's protocols, which only the app does.

// MARK: - Clipboard (ClipboardProviding backed by the live ClipboardMonitor)

/// `ClipboardProviding` backed by the app's running `ClipboardMonitor`.
///
/// The monitor owns the privacy-filtered, in-memory history (populated by the
/// poll driver). `history` reads straight from it (fuzzy-ranked when a query is
/// present); `copy` writes the item's text onto the general pasteboard so a
/// plugin's "copy" actually lands on the system clipboard, then records it at the
/// head of history (and bumps the monitor's change count via the OS) — the next
/// poll would otherwise re-capture it, so we latch `ignoreNextCopy` to avoid a
/// duplicate entry.
///
/// The monitor is `@MainActor`-friendly (the poll driver ticks on the main queue
/// and `NSPasteboard` is main-thread). The engine's bridge invokes these from its
/// serial queue and always hops back, so we marshal onto the main thread before
/// touching the monitor / pasteboard.
final class ClipboardMonitorProvider: ClipboardProviding {
    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    func history(query: String,
                 limit: Int,
                 completion: @escaping (Result<[ClipboardItem], Error>) -> Void) {
        let monitor = self.monitor
        runOnMain {
            completion(.success(monitor.history(query: query, limit: limit)))
        }
    }

    func copy(_ item: ClipboardItem, completion: @escaping (Result<Void, Error>) -> Void) {
        let monitor = self.monitor
        runOnMain {
            // Don't double-record: the write below bumps NSPasteboard.changeCount,
            // which the poll driver would otherwise capture as a fresh item.
            monitor.ignoreNextCopy()
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(item.text, forType: .string)
            completion(.success(()))
        }
    }

    /// Run `body` on the main thread (synchronously if already there). The engine
    /// bridge tolerates a synchronous completion (it hops to its own queue), so a
    /// direct call when already on main is correct and avoids a needless dispatch.
    private func runOnMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            DispatchQueue.main.async { body() }
        }
    }
}

// MARK: - Calendar (CalendarProviding backed by EventKit, lazy TCC)

#if canImport(EventKit)
import EventKit

/// `CalendarProviding` backed by EventKit, adapting the VeeServices
/// `CalendarService` (which sorts + runs `MeetingLinkDetector`) to the engine's
/// wire-`CalendarEvent` protocol.
///
/// Access is requested LAZILY on the first `upcoming` call (never at launch, so a
/// TCC prompt can't block app startup) and remembered. If access isn't granted —
/// not-yet-asked-and-denied, restricted, or any error — it returns `[]` rather
/// than throwing, so a `calendar:true` plugin sees "no upcoming meetings" instead
/// of a crash or error spinner. Requires `NSCalendarsFullAccessUsageDescription`
/// in the packaged app's Info.plist (the lead owns packaging).
///
/// Thread-safe: a lock guards the cached authorization flag; `EKEventStore` is
/// itself safe to use across threads for these read APIs. The engine bridge calls
/// `upcoming` from its serial queue and hops back, so we resolve synchronously
/// here (requesting access blocks this call's worker, never the main thread).
final class EventKitCalendarAdapter: CalendarProviding {
    private let store = EKEventStore()
    /// How far ahead to surface events (24h, matching a "today/next up" view).
    private let window: TimeInterval
    private let lock = NSLock()
    /// nil = not yet requested; true/false = the remembered grant decision.
    private var granted: Bool?

    init(window: TimeInterval = 60 * 60 * 24) {
        self.window = window
    }

    func upcoming(completion: @escaping (Result<[CalendarEvent], Error>) -> Void) {
        ensureAccess { [weak self] ok in
            guard let self, ok else { completion(.success([])); return }
            let service = CalendarService(
                provider: EventKitCalendarProvider(store: self.store),
                clock: SystemClock())
            completion(.success(service.upcoming(within: self.window)))
        }
    }

    /// Resolve (and cache) full-access authorization. Already-authorized status
    /// short-circuits the prompt; otherwise we request once and remember. The
    /// completion is invoked on whatever thread EventKit calls back on — the
    /// caller (engine bridge) re-marshals, so that's fine.
    private func ensureAccess(_ done: @escaping (Bool) -> Void) {
        lock.lock()
        if let granted {
            lock.unlock()
            done(granted)
            return
        }
        lock.unlock()

        // If the system already records full access, skip the prompt entirely.
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            remember(true)
            done(true)
            return
        }

        store.requestFullAccessToEvents { [weak self] ok, _ in
            self?.remember(ok)
            done(ok)
        }
    }

    private func remember(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        granted = value
    }
}
#endif

// MARK: - Keychain → TokenStoring (Settings window secret storage)

/// Adapts `VeeKeychain.KeychainStore` to `VeeApp.TokenStoring` for the Settings
/// window. VeeApp deliberately doesn't depend on VeeKeychain, so the executable
/// supplies this bridge. The keychain namespace is PINNED to `"tokens"` (the
/// settings surface's fixed namespace); the UI's `plugin`/`account` axes map onto
/// the keychain's `pluginId`/`account`, producing a `kSecAttrService` of
/// `com.vee.<plugin>.tokens`.
///
/// Keychain calls can throw (locked keychain, OS errors); `TokenStoring` is
/// throwing-free by contract, so failures are swallowed to a safe result (a read
/// failure reads as "no token", a write/delete failure is dropped). That keeps
/// the settings UI non-crashing; the keychain is the source of truth on success.
final class KeychainTokenStore: TokenStoring {
    /// The fixed namespace all settings-managed tokens live under.
    static let namespace = "tokens"

    private let backing: KeychainStore

    init(backing: KeychainStore = KeychainStore()) {
        self.backing = backing
    }

    func token(plugin: String, account: String) -> String? {
        (try? backing.get(pluginId: plugin,
                          namespace: KeychainTokenStore.namespace,
                          account: account)) ?? nil
    }

    func setToken(_ token: String, plugin: String, account: String) {
        // Empty string clears, mirroring the secure field's "erase" gesture and
        // `InMemoryTokenStore`'s behavior.
        if token.isEmpty {
            deleteToken(plugin: plugin, account: account)
            return
        }
        try? backing.set(pluginId: plugin,
                         namespace: KeychainTokenStore.namespace,
                         account: account,
                         secret: token)
    }

    func deleteToken(plugin: String, account: String) {
        try? backing.delete(pluginId: plugin,
                            namespace: KeychainTokenStore.namespace,
                            account: account)
    }
}
