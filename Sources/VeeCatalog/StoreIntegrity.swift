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
    ///   - signingKeyBase64: The base64 Ed25519 public key (policy-pinned key, or
    ///     the manifest's), if available.
    ///   - requireSignature: Whether the store mandates a valid signature.
    public static func verify(
        source: String,
        declaredSHA256: String?,
        signatureBase64: String?,
        signingKeyBase64: String?,
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
        // A present signature is always validated — a wrong signature fails even
        // when the store doesn't strictly require one.
        if hasSignature {
            guard let signatureBase64,
                  let signingKeyBase64,
                  isValidSignature(source: source, signatureBase64: signatureBase64, keyBase64: signingKeyBase64)
            else {
                return .signatureInvalid
            }
        }
        return .ok
    }

    /// Convenience over ``verify(source:declaredSHA256:signatureBase64:signingKeyBase64:requireSignature:)``
    /// resolving the signing key as the store's pinned key or the manifest's.
    public static func verify(source: String, entry: CatalogEntry, store: StoreConfig, manifestSigningKey: String? = nil) -> Verdict {
        verify(
            source: source,
            declaredSHA256: entry.declaredSHA256,
            signatureBase64: entry.signature,
            signingKeyBase64: store.pinnedSigningKey ?? manifestSigningKey,
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
