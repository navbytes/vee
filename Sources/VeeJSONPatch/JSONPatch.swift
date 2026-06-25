import Foundation
import VeeProtocol

/// RFC 6902 (JSON Patch) compute + apply over `JSONValue`. The wire *types*
/// (`PatchOp`, `JSONPatchError`) live in `VeeProtocol`; the *algorithms* live
/// here so the frozen contract stays dependency-free and rarely recompiles.
///
/// > Wave 1d worker: implement full `diff` (minimal patches, array moves) and
/// > `apply` (all 6 ops, RFC 6901 pointer escaping `~0`/`~1`, `/-` append) per
/// > build plan §4. Headline gate: `apply(diff(a,b), a) == b` over 1000
/// > randomized trees. Tests first.
public enum JSONPatch {
    /// Compute a patch that transforms `a` into `b`.
    public static func diff(_ a: JSONValue, _ b: JSONValue) -> JSONPatchDocument {
        // Wave 0 stub: whole-document replace (correct, just not minimal).
        a == b ? [] : [.replace("", b)]
    }

    /// Apply a patch to `document`, returning the new document.
    public static func apply(_ patch: JSONPatchDocument, to document: JSONValue) throws -> JSONValue {
        // Wave 0 stub: handles only replace-root. Replaced in Wave 1d (TDD).
        var doc = document
        for op in patch {
            guard op.op == .replace, op.path == "", let value = op.value else {
                throw JSONPatchError.invalidPointer(op.path)
            }
            doc = value
        }
        return doc
    }
}
