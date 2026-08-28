import CryptoKit
import Foundation

/// Verifies a fetched plugin source against a store's integrity guarantees:
/// a manifest-pinned SHA-256 and an optional Ed25519 signature. Pure — no I/O —
/// so it is fully unit-testable. `CryptoKit` is an Apple system framework, so
/// this adds no third-party dependency.
public enum StoreIntegrity {
    /// The outcome of verifying a source against a store's policy.
    public enum Verdict: Equatable, Sendable {
        /// Passed every applicable check.
        case ok
        /// The source doesn't match the manifest-pinned hash.
        case hashMismatch
        /// A signature was required (or advertised) but couldn't be validated.
        case signatureInvalid
        /// The store requires a signature and none was provided.
        case signatureMissing
        /// The store requires a signature, one was provided, but the only key
        /// available to check it came from the same manifest as the signature.
        case signatureUnpinned

        /// Whether the install should be allowed to proceed.
        public var passes: Bool { self == .ok }
    }

    /// Verifies `source` against the pins/policy expressed as primitives — the
    /// testable core.
    ///
    /// - Parameters:
    ///   - source: The fetched plugin source.
    ///   - declaredSHA256: The manifest-pinned lowercase-hex SHA-256, if any.
    ///   - signatureBase64: A base64 Ed25519 signature over the source's SHA-256
    ///     digest, if the entry is signed.
    ///   - pinnedKeyBase64: The base64 Ed25519 public key pinned by local policy.
    ///     This is the only key that can establish *who* signed something.
    ///   - manifestKeyBase64: The key the store's own manifest advertises. Used
    ///     to catch corruption, never to establish provenance — it arrives from
    ///     the same place as the signature, so whoever can change one can change
    ///     the other. A "signature" checked only against it proves that a file
    ///     matches a manifest, which the SHA-256 pin already proves.
    ///   - requireSignature: Whether the store mandates a valid signature.
    public static func verify(
        source: String,
        declaredSHA256: String?,
        signatureBase64: String?,
        pinnedKeyBase64: String?,
        manifestKeyBase64: String? = nil,
        requireSignature: Bool
    ) -> Verdict {
        if let declared = declaredSHA256, !declared.isEmpty {
            if PluginHash.sha256Hex(source).caseInsensitiveCompare(declared) != .orderedSame {
                return .hashMismatch
            }
        }

        let hasSignature = (signatureBase64?.isEmpty == false)
        if requireSignature && !hasSignature {
            return .signatureMissing
        }
        // A store that requires signatures is asking for proof of WHO produced
        // the plugin, and only a locally-pinned key can answer that. Without
        // one, the manifest supplies both the signature and the key used to
        // check it, so a compromised store just signs with a key of its own
        // choosing and the check passes while proving nothing. Fail rather than
        // report a guarantee that isn't there.
        if requireSignature && pinnedKeyBase64 == nil {
            return .signatureUnpinned
        }
        // A present signature is always validated — a wrong signature fails even
        // when the store doesn't strictly require one. The manifest key is
        // allowed here, where the job is only detecting corruption: a store that
        // advertises a signature and gets it wrong is broken either way.
        if hasSignature, let key = pinnedKeyBase64 ?? manifestKeyBase64 {
            guard let signatureBase64,
                  isValidSignature(source: source, signatureBase64: signatureBase64, keyBase64: key)
            else {
                return .signatureInvalid
            }
        }
        return .ok
    }

    /// Convenience over the primitive, keeping the store's pinned key and the
    /// manifest's advertised key distinct — they are not interchangeable.
    public static func verify(source: String, entry: CatalogEntry, store: StoreConfig, manifestSigningKey: String? = nil) -> Verdict {
        verify(
            source: source,
            declaredSHA256: entry.declaredSHA256,
            signatureBase64: entry.signature,
            pinnedKeyBase64: store.pinnedSigningKey,
            manifestKeyBase64: manifestSigningKey,
            requireSignature: store.requireSignature
        )
    }

    /// Validates an Ed25519 signature over `SHA256(source)`.
    static func isValidSignature(source: String, signatureBase64: String, keyBase64: String) -> Bool {
        guard let signature = Data(base64Encoded: signatureBase64),
              let keyData = Data(base64Encoded: keyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        let digest = Data(SHA256.hash(data: Data(source.utf8)))
        return key.isValidSignature(signature, for: digest)
    }
}
