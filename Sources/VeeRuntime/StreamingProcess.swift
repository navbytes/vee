import Foundation
import VeeCore

/// Launches a long-lived process and streams its stdout as lines until it exits.
public protocol StreamingProcessRunning: Sendable {
    func lines(_ invocation: ProcessInvocation) -> AsyncThrowingStream<String, Error>
}

/// Production streaming runner backed by `Process`.
public struct SystemStreamingRunner: StreamingProcessRunning {
    public init() {}

    public func lines(_ invocation: ProcessInvocation) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let proc = StreamingProc(invocation: invocation, continuation: continuation)
            continuation.onTermination = { _ in proc.cancel() }
            proc.start()
        }
    }
}

/// Owns the non-`Sendable` process machinery for one streaming run, splitting
/// incoming data into lines. `@unchecked Sendable`: state is guarded by `lock`.
private final class StreamingProc: @unchecked Sendable {
    private let invocation: ProcessInvocation
    private let continuation: AsyncThrowingStream<String, Error>.Continuation

    private let process = Process()
    private let outPipe = Pipe()
    private let lock = NSLock()
    private var partial = Data()
    private var finished = false
    private var selfRetain: StreamingProc?

    init(invocation: ProcessInvocation, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.invocation = invocation
        self.continuation = continuation
    }

    func start() {
        selfRetain = self
        process.executableURL = URL(fileURLWithPath: invocation.launchPath)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        if let wd = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            finish(error: VeeError.launchFailed(pluginID: PluginID(path: invocation.launchPath), reason: error.localizedDescription))
            return
        }
        // Close the parent's write end so the read loop sees EOF at child exit.
        try? outPipe.fileHandleForWriting.close()

        // Single dedicated reader: `availableData` blocks until data arrives or
        // EOF (empty). This delivers every line — including the tail — without
        // racing a termination handler, which was the source of a CI flake.
        let handle = outPipe.fileHandleForReading
        DispatchQueue.global().async { [self] in
            while true {
                let data = handle.availableData
                if data.isEmpty { break } // EOF
                ingest(data)
            }
            finish(error: nil)
        }
    }

    private func ingest(_ data: Data) {
        var linesToYield: [String] = []
        lock.withLock {
            partial.append(data)
            while let nl = partial.firstIndex(of: 0x0A) {
                let lineData = partial[partial.startIndex..<nl]
                linesToYield.append(String(decoding: lineData, as: UTF8.self))
                partial.removeSubrange(partial.startIndex...nl)
            }
        }
        for line in linesToYield { continuation.yield(line) }
    }

    private func finish(error: Error?) {
        let alreadyFinished: Bool = lock.withLock {
            if finished { return true }
            finished = true
            return false
        }
        guard !alreadyFinished else { return }

        // Emit any trailing partial line (output with no final newline).
        let tail: String? = lock.withLock {
            guard !partial.isEmpty else { return nil }
            let s = String(decoding: partial, as: UTF8.self)
            partial.removeAll()
            return s
        }
        if let tail { continuation.yield(tail) }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        selfRetain = nil
    }

    func cancel() {
        if process.isRunning { process.terminate() }
        finish(error: nil)
    }
}
