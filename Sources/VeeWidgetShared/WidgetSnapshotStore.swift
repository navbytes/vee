import Foundation

/// Shared constants and the read/write plumbing that lets the app publish plugin
/// output for the widget/control extension.
///
/// **Why a plain file, not an App Group.** Vee's app is intentionally
/// un-sandboxed (it runs arbitrary plugins). A non-sandboxed process cannot
/// write into an App Group container at all (`NSCocoaErrorDomain 513`,
/// "Operation not permitted"), and a group-suite `UserDefaults` is scoped per
/// *container* for the sandboxed widget but *globally* for the non-sandboxed
/// app — so the two never meet. Instead the app writes a JSON file under
/// `~/Library/Application Support/Vee/`, and the sandboxed widget reads it via a
/// `temporary-exception.files.home-relative-path.read-only` entitlement.
public enum VeeWidgetSharing {
    /// Darwin notification the app observes so a control-triggered refresh is
    /// picked up immediately while the app is already running. (A cold start is
    /// covered by the control's `openAppWhenRun`, since Vee refreshes every
    /// plugin on launch.)
    public static let refreshRequestNotification = "com.vee.control.refreshAllRequested"

    static let snapshotFileName = "widget-snapshot.json"

    /// The real `~/Library/Application Support/Vee` directory, resolved through
    /// the password database (`getpwuid`) rather than `FileManager`. A sandboxed
    /// extension's `FileManager`/`NSHomeDirectory` would redirect into its own
    /// container; `pw_dir` returns the true home on both sides so the app and
    /// the widget agree on one path.
    public static func supportDirectory() -> URL {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Vee", isDirectory: true)
    }

    /// The store backed by the shared support directory. Always resolvable (the
    /// app creates the directory on first write).
    public static var shared: WidgetSnapshotStore {
        WidgetSnapshotStore(directory: supportDirectory())
    }
}

/// Reads and writes the shared `WidgetSnapshot` JSON under a directory. The app
/// writes it; the widget reads it. Injecting the directory keeps the JSON
/// round-trip unit-testable against a temp directory.
public struct WidgetSnapshotStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(VeeWidgetSharing.snapshotFileName) }

    /// Encodes and writes `snapshot` atomically. Called by the app (which can
    /// write here freely). Silently no-ops on failure — the widget keeps its
    /// previous timeline rather than crashing.
    public func write(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Reads the current snapshot, or `nil` if none has been written or it can't
    /// be decoded. Called by the widget (read-only via a sandbox exception).
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
