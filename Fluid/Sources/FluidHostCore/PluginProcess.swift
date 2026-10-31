import Foundation
import FluidProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// One running plugin helper and the pipes to it.
///
/// stdout and stderr are each drained on their own thread until EOF, so a
/// plugin that writes a lot can never block on a full pipe, and stdout lines go
/// through a capped `LineBuffer`. Writes to a plugin that has already exited
/// fail quietly instead of killing the host: `SIGPIPE` is ignored process-wide
/// the first time a helper starts.
///
/// ponytail: launched with Foundation's `Process`, so a helper is not the
/// leader of its own process group and a timeout reaps only the helper, not
/// anything it spawned. Vee's `SystemProcessRunner` already solves this with
/// `posix_spawn` + `killpg`; it moves into the shared package in phase 1 and
/// replaces this launch path.
public final class PluginProcess: @unchecked Sendable {
    public enum Event: Sendable {
        case message(PluginMessage)
        case stderr(String)
        case undecodable(String)
        case exit(Int32)
    }

    public let executable: URL
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let writeLock = NSLock()

    public init(executable: URL, arguments: [String] = [], environment: [String: String]? = nil) {
        self.executable = executable
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
    }

    public var processIdentifier: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }

    /// Starts the helper. `onEvent` is called from background threads, in
    /// order per pipe; `.exit` comes last, after both pipes reached EOF.
    public func start(onEvent: @escaping @Sendable (Event) -> Void) throws {
        Self.ignoreSIGPIPE
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let drained = DispatchGroup()
        drained.enter()
        drained.enter()
        drained.enter()
        process.terminationHandler = { _ in drained.leave() }
        try process.run()

        Self.drain(stdoutPipe.fileHandleForReading, group: drained) { line in
            if let message = try? LineCodec.decode(PluginMessage.self, from: line) {
                onEvent(.message(message))
            } else {
                onEvent(.undecodable(String(decoding: line, as: UTF8.self)))
            }
        }
        Self.drain(stderrPipe.fileHandleForReading, group: drained) { line in
            onEvent(.stderr(String(decoding: line, as: UTF8.self)))
        }
        let process = process
        drained.notify(queue: .global()) {
            onEvent(.exit(process.terminationStatus))
        }
    }

    public func send(_ message: HostMessage) {
        guard let data = try? LineCodec.encode(message) else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    /// Asks the helper to exit, then escalates: SIGTERM after `grace`, SIGKILL
    /// after another `grace`.
    public func terminate(grace: Double = 2) {
        send(.shutdown)
        try? stdinPipe.fileHandleForWriting.close()
        let pid = process.processIdentifier
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// Runs `executable --manifest` and decodes what it prints.
    public static func readManifest(executable: URL, timeout: Double = 15) throws -> Manifest {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--manifest"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ManifestError.timedOut(executable.path)
        }
        do {
            return try LineCodec.decode(Manifest.self, from: data)
        } catch {
            throw ManifestError.unreadable(executable.path, String(decoding: data.prefix(500), as: UTF8.self))
        }
    }

    public enum ManifestError: Error, CustomStringConvertible {
        case timedOut(String)
        case unreadable(String, String)

        public var description: String {
            switch self {
            case .timedOut(let path): return "\(path) did not print its manifest in time"
            case .unreadable(let path, let output): return "\(path) printed no valid manifest: \(output)"
            }
        }
    }

    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private static func drain(_ handle: FileHandle, group: DispatchGroup, onLine: @escaping @Sendable (Data) -> Void) {
        let thread = Thread {
            var buffer = LineBuffer()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                for line in buffer.append(chunk) { onLine(line) }
            }
            group.leave()
        }
        thread.start()
    }
}
