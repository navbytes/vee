import Foundation

/// A JSON-file-backed store that persists across process / instance lifetimes.
///
/// Each key maps to one file inside a caller-provided directory (never a
/// hardcoded user path — the host passes a per-command support folder; tests
/// pass a temp dir). Values are encoded with `JSONEncoder`, so `Value` must be
/// `Codable`.
///
/// A single `NSLock` serializes filesystem access, making the type `Sendable`
/// and safe for the concurrent access ``SWRCache`` performs.
public final class DiskStorage<Value>: CacheStrategy, @unchecked Sendable
    where Value: Codable & Sendable {

    private let lock = NSLock()
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter directory: directory to store entry files under. Created if
    ///   it does not exist. Callers own its lifecycle (and cleanup).
    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func get(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    public func set(_ key: String, value: Value) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? encoder.encode(value) else { return }
        // Write atomically so a crash mid-write can never leave a torn file.
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    public func invalidate(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    // MARK: Key → file mapping

    /// Map an arbitrary key to a safe, collision-free filename. We percent-
    /// encode everything that is not alphanumeric so keys with `/`, `.`, etc.
    /// cannot escape the directory or clash.
    private func fileURL(for key: String) -> URL {
        let safe = Self.encode(key)
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    private static func encode(_ key: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return key.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%", with: "_") ?? key
    }
}
