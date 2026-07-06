import Foundation

/// Accumulates the stdout lines of a streamable plugin and emits a complete
/// output block each time the `~~~` separator is seen. SwiftBar resets the menu
/// on every `~~~`, so each block is a full menu render.
public struct StreamAccumulator {
    public static let separator = "~~~"

    /// Upper bound on bytes buffered between `~~~` separators. A streaming plugin
    /// that emits forever without a separator would otherwise grow this buffer
    /// without limit, breaking the bounded-memory guarantee. A single menu render
    /// this large is already pathological; past the cap we stop appending (the
    /// block is truncated) until the next separator resets us.
    public static let maxBufferedBytes = 4 * 1024 * 1024

    private var buffer: [String] = []
    private var bufferedBytes = 0

    public init() {}

    /// Consumes one line. Returns the accumulated block (as a single string)
    /// when the line is a `~~~` separator, otherwise `nil`.
    public mutating func consume(_ line: String) -> String? {
        if line == Self.separator {
            let block = buffer.joined(separator: "\n")
            buffer.removeAll(keepingCapacity: true)
            bufferedBytes = 0
            return block
        }
        if bufferedBytes < Self.maxBufferedBytes {
            buffer.append(line)
            bufferedBytes += line.utf8.count + 1 // +1 for the joining newline
        }
        return nil
    }

    /// Emits any remaining buffered lines (e.g. when the stream ends without a
    /// trailing separator). Returns `nil` if nothing is buffered.
    public mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let block = buffer.joined(separator: "\n")
        buffer.removeAll(keepingCapacity: true)
        bufferedBytes = 0
        return block
    }
}
