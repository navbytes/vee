import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The plugin side of the pipe: host messages on stdin, plugin messages on a
/// private copy of stdout.
///
/// At start-up the real stdout is duplicated for the protocol and file
/// descriptor 1 is pointed at stderr. A stray `print()` in plugin code then
/// lands in the host's log instead of corrupting the message stream — an easy
/// mistake to make, and the kind an AI-written plugin will make.
final class StdioTransport: Sendable {
    private let output: FileHandle
    private let lock = NSLock()

    init() {
        let protocolFD = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        output = FileHandle(fileDescriptor: protocolFD, closeOnDealloc: true)
    }

    var send: PluginRuntime.Send {
        { [self] message in
            guard let data = try? LineCodec.encode(message) else { return }
            // Flush C stdio (where `print` buffers, now pointed at stderr) so a
            // stray print reaches the log alongside the message it preceded.
            fflush(nil)
            lock.lock()
            defer { lock.unlock() }
            output.write(data)
        }
    }

    /// Host messages, read on a dedicated thread so a blocking read never
    /// holds the main actor. Undecodable lines are skipped; EOF ends the stream.
    func incoming() -> AsyncStream<HostMessage> {
        AsyncStream { continuation in
            // Raw reads, not `readLine`: a thread parked in C stdio's stdin
            // would hold a lock that the `fflush(nil)` in `send` also takes.
            let reader = Thread {
                let input = FileHandle.standardInput
                var buffer = LineBuffer()
                while true {
                    let chunk = input.availableData
                    if chunk.isEmpty { break }
                    for line in buffer.append(chunk) {
                        if let message = try? LineCodec.decode(HostMessage.self, from: line) {
                            continuation.yield(message)
                        }
                    }
                }
                continuation.finish()
            }
            reader.start()
        }
    }

    static func printManifest(_ manifest: Manifest) {
        guard let data = try? LineCodec.encode(manifest) else { return }
        FileHandle.standardOutput.write(data)
    }
}
