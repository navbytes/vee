import Foundation
import VeeProtocol
import VeeCache

/// A disk-backed `StorageBackend` so `vee.storage.get`/`set` survive across
/// launches.
///
/// Backed by VeeCache's ``DiskStorage`` (one JSON file per key) under a
/// caller-provided directory. The store is namespaced by plugin id — each
/// plugin gets its own `<directory>/<sanitized-pluginId>/` subfolder — so two
/// plugins pointed at the same root directory never read or clobber each
/// other's keys (mirroring the per-plugin isolation `keychainServiceString`
/// gives secrets).
///
/// `InMemoryStorage` remains the engine/host default (so the existing suite is
/// unaffected); `DiskStorageBackend` is opt-in — the app wires it via the
/// `PluginInstance`/`PluginHost` `storage`/`storageFactory` parameter.
///
/// ## TTL
/// `StorageBackend.set(_:value:ttlSeconds:)` carries an optional TTL. The
/// in-memory default ignores it; the disk backend persists each value in a
/// small ``Envelope`` carrying an optional absolute expiry. A `get` past the
/// expiry returns `nil` (and best-effort evicts the file), so a persisted value
/// with a TTL does not outlive it across launches. A `nil` TTL never expires —
/// the same observable behaviour as `InMemoryStorage` for the no-TTL path.
///
/// ## File protection
/// On a best-effort basis the store directory and every per-key file are tagged
/// with a `FileProtectionType` (default `.complete`) so the on-disk bytes are
/// encrypted at rest where the platform supports it (iOS; a no-op on most
/// macOS volumes). Failures to apply protection are swallowed — the store still
/// works, it is just not additionally protected.
///
/// Thread-safe: ``DiskStorage`` serializes all filesystem access under its own
/// lock, and `Envelope` coding is value-only, so `DiskStorageBackend` is safe
/// to share across the instance's serial queue and any background completion.
public final class DiskStorageBackend: StorageBackend {

    /// On-disk wrapper: the stored value plus an optional absolute expiry
    /// (seconds since the reference date). Codable so it round-trips through
    /// ``DiskStorage``.
    private struct Envelope: Codable, Sendable {
        var value: JSONValue
        /// Absolute expiry instant; `nil` means "never expires".
        var expiresAt: Date?
    }

    private let store: DiskStorage<Envelope>
    /// The per-plugin directory this backend owns (already created).
    public let directory: URL
    private let fileProtection: URLFileProtection?
    /// Injected so tests can pin "now"; production uses the real wall clock.
    private let now: () -> Date

    /// Create a disk-backed store for one plugin.
    ///
    /// - Parameters:
    ///   - directory: the *root* support directory the caller owns (never a
    ///     hardcoded user path). The backend creates and uses a per-plugin
    ///     subfolder beneath it.
    ///   - pluginId: namespaces this plugin's keys under `directory`.
    ///   - fileProtection: protection class to apply to the directory + files,
    ///     best-effort. Defaults to `.complete`. Pass `nil` to skip entirely.
    ///   - now: time source for TTL expiry (defaults to `Date()`).
    public init(
        directory: URL,
        pluginId: String,
        fileProtection: URLFileProtection? = .complete,
        now: @escaping () -> Date = Date.init
    ) throws {
        let pluginDirectory = directory.appendingPathComponent(
            DiskStorageBackend.sanitize(pluginId), isDirectory: true)
        self.directory = pluginDirectory
        self.fileProtection = fileProtection
        self.now = now
        // DiskStorage creates the directory (with intermediates) on init.
        self.store = try DiskStorage<Envelope>(directory: pluginDirectory)
        // Best-effort: tag the directory so files created under it inherit the
        // protection class where the platform honours it.
        applyProtection(to: pluginDirectory)
    }

    // MARK: - StorageBackend

    public func get(_ key: String) -> JSONValue? {
        guard let envelope = store.get(key) else { return nil }
        if let expiresAt = envelope.expiresAt, expiresAt <= now() {
            // Expired: evict and report absent.
            store.invalidate(key)
            return nil
        }
        return envelope.value
    }

    public func set(_ key: String, value: JSONValue, ttlSeconds: Double?) {
        let expiresAt: Date? = ttlSeconds.flatMap { ttl in
            ttl.isFinite ? now().addingTimeInterval(ttl) : nil
        }
        store.set(key, value: Envelope(value: value, expiresAt: expiresAt))
        // Re-apply protection to the freshly written file (best-effort).
        applyProtection(to: fileURL(for: key))
    }

    // MARK: - File protection (best-effort, never throws)

    /// Apply at-rest protection to a directory or file. Best-effort and never
    /// throws — the store keeps working even if nothing can be applied.
    ///
    /// - On platforms with data protection (iOS/iPadOS, where `UIKit` and the
    ///   `URLFileProtection` write path exist) the configured protection class
    ///   is set via `URLResourceValues.fileProtection`.
    /// - On macOS that write API is unavailable (`fileProtection` is read-only
    ///   and most volumes have no per-file data protection), so we instead
    ///   tighten POSIX permissions to owner-only (`0o700` for the directory,
    ///   `0o600` for files) as the portable best-effort hardening.
    private func applyProtection(to url: URL) {
        guard fileProtection != nil else { return }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        #if canImport(UIKit)
        // Data-protection-capable platforms: set the protection class directly.
        if let fileProtection {
            var mutable = url
            var values = URLResourceValues()
            values.fileProtection = fileProtection
            try? mutable.setResourceValues(values)
        }
        #else
        // macOS / others: no per-file data protection write path. Fall back to
        // restricting access to the owner so the bytes are not world-readable.
        let perms = isDirectory.boolValue ? 0o700 : 0o600
        try? fm.setAttributes([.posixPermissions: NSNumber(value: perms)],
                              ofItemAtPath: url.path)
        #endif
    }

    /// Mirror of ``DiskStorage``'s key→file mapping so we can re-protect the
    /// exact file a `set` wrote. Kept in sync with `DiskStorage.encode`.
    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(DiskStorageBackend.encodeKey(key))
            .appendingPathExtension("json")
    }

    private static func encodeKey(_ key: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return key.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%", with: "_") ?? key
    }

    /// Sanitize a plugin id into a safe single path component (reverse-DNS ids
    /// contain dots, which are fine, but we strip path separators defensively).
    private static func sanitize(_ pluginId: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        return pluginId.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%", with: "_") ?? pluginId
    }
}
