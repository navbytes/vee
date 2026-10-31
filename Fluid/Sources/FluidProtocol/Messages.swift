import Foundation

/// The protocol version a host and plugin agree on in `hello`/`ready`.
public enum FluidProtocolVersion {
    public static let current = 1
}

/// Host → plugin.
public enum HostMessage: Codable, Equatable, Sendable {
    /// The first message. The plugin answers with `ready`, then renders.
    case hello(protocolVersion: Int, surfaces: [Surface])
    /// Run `refresh()`, then re-render.
    case trigger(reason: TriggerReason)
    /// The user acted on something the plugin rendered.
    case event(action: ActionID, value: EventValue?)
    /// A surface opened or closed (the panel, mostly).
    case visibility(surface: Surface, visible: Bool)
    /// Exit cleanly; the host kills the process if it doesn't.
    case shutdown
}

public enum TriggerReason: String, Codable, Sendable {
    case launch, interval, wake, manual
}

/// The value that came with an event: a toggle's new state, a slider's number.
public enum EventValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case text(String)
}

/// Plugin → host.
public enum PluginMessage: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int)
    /// The whole tree for one surface. Sent only when it changed.
    case render(surface: Surface, root: ViewNode)
    case log(level: LogLevel, message: String)
    /// Sent after every host message has been fully handled (refresh or action
    /// done, renders sent). Lets a host or a test know the plugin is quiet.
    case settled
}

public enum LogLevel: String, Codable, Sendable {
    case debug, info, warning, error
}

/// Newline-delimited JSON: one message per line on the plugin's stdin/stdout.
///
/// JSON keeps a misbehaving plugin debuggable with nothing but a terminal, and
/// the encoder never emits a raw newline inside a value, so a line is always
/// exactly one message.
public enum LineCodec {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}

/// Splits a byte stream into lines, holding a partial line across reads.
///
/// A line longer than `maxLineBytes` is dropped (and counted) rather than
/// buffered without bound, the same cap Vee puts on a plugin's stdout, so a
/// plugin that never writes a newline can't grow the host's memory forever.
public struct LineBuffer: Sendable {
    public static let defaultMaxLineBytes = 8 * 1024 * 1024

    public let maxLineBytes: Int
    public private(set) var droppedLines = 0
    private var pending = Data()
    private var discarding = false

    public init(maxLineBytes: Int = LineBuffer.defaultMaxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    /// Appends a chunk and returns every line it completed, without newlines.
    public mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let piece = chunk[start..<newline]
            if discarding {
                discarding = false
            } else if pending.count + piece.count <= maxLineBytes {
                var line = pending
                line.append(piece)
                if !line.isEmpty { lines.append(line) }
            } else {
                droppedLines += 1
            }
            pending.removeAll(keepingCapacity: true)
            start = chunk.index(after: newline)
        }
        let rest = chunk[start...]
        if discarding {
            return lines
        }
        if pending.count + rest.count > maxLineBytes {
            pending.removeAll()
            discarding = true
            droppedLines += 1
        } else {
            pending.append(rest)
        }
        return lines
    }
}
