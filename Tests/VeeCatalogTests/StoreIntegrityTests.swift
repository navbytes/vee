import XCTest
import CryptoKit
@testable import VeeCatalog

final class StoreIntegrityTests: XCTestCase {
    private let source = "#!/bin/bash\necho hi\n"

    // MARK: - Hash pinning

    func testMatchingHashPasses() {
        let hash = PluginHash.sha256Hex(source)
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: hash, signatureBase64: nil, pinnedKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    func testWrongHashFails() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: "deadbeef", signatureBase64: nil, pinnedKeyBase64: nil, requireSignature: false),
            .hashMismatch
        )
    }

    func testHashIsCaseInsensitive() {
        let hash = PluginHash.sha256Hex(source).uppercased()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: hash, signatureBase64: nil, pinnedKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    func testNoHashSkipsHashCheck() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: nil, pinnedKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    // MARK: - Signatures

    private func sign(_ source: String, key: Curve25519.Signing.PrivateKey) throws -> String {
        let digest = Data(SHA256.hash(data: Data(source.utf8)))
        return try key.signature(for: digest).base64EncodedString()
    }

    func testValidSignaturePasses() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try sign(source, key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, pinnedKeyBase64: pub, requireSignature: true),
            .ok
        )
    }

    func testSignatureOverDifferentSourceFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try sign("something else", key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, pinnedKeyBase64: pub, requireSignature: true),
            .signatureInvalid
        )
    }

    func testWrongKeyFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try sign(source, key: key)
        let otherPub = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, pinnedKeyBase64: otherPub, requireSignature: true),
            .signatureInvalid
        )
    }

    func testRequiredSignatureMissingFails() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: nil, pinnedKeyBase64: nil, requireSignature: true),
            .signatureMissing
        )
    }

    func testUnrequiredButPresentSignatureStillValidated() throws {
        // A wrong signature fails even when the store doesn't require signing.
        let key = Curve25519.Signing.PrivateKey()
        let sig = try sign("tampered", key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, pinnedKeyBase64: pub, requireSignature: false),
            .signatureInvalid
        )
    }

    // MARK: - Convenience over entry + store

    func testConvenienceResolvesPinnedKeyOverManifest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try sign(source, key: key)
        let pinned = key.publicKey.rawRepresentation.base64EncodedString()
        var store = StoreConfig(id: StoreID("s"), displayName: "S", kind: .github, requireSignature: true, pinnedSigningKey: pinned)
        store.requireSignature = true
        let entry = CatalogEntry(storeID: StoreID("s"), path: "A/x.sh", category: "A", filename: "x.sh",
                                 rawURL: URL(string: "https://x")!, signature: sig)
        // A different manifest key would fail; the pinned key wins and passes.
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, entry: entry, store: store, manifestSigningKey: "bogus"),
            .ok
        )
    }
    /// A store that demands signatures but pins no key is asking for a
    /// guarantee it cannot get: the manifest supplies the signature AND the key
    /// used to check it, so whoever can rewrite one can rewrite the other. That
    /// check passed while proving nothing more than the SHA-256 pin already did.
    func testRequireSignatureIsNotSatisfiedByAManifestSuppliedKey() throws {
        let source = "echo hi"
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let sig = try key.signature(for: Data(SHA256.hash(data: Data(source.utf8)))).base64EncodedString()

        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig,
                                  pinnedKeyBase64: nil, manifestKeyBase64: pub, requireSignature: true),
            .signatureUnpinned,
            "a self-supplied key cannot satisfy a signature requirement")

        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig,
                                  pinnedKeyBase64: pub, manifestKeyBase64: nil, requireSignature: true),
            .ok,
            "the same signature against a PINNED key is exactly what the policy asks for")
    }

    /// The manifest key keeps its one honest job: catching a store that
    /// advertises a signature and gets it wrong. That is corruption detection,
    /// not provenance, and it must not start passing silently.
    func testManifestKeyStillCatchesAWrongSignatureWhenNotRequired() throws {
        let source = "echo hi"
        let other = Curve25519.Signing.PrivateKey()
        let wrongSig = try other.signature(for: Data(SHA256.hash(data: Data("something else".utf8)))).base64EncodedString()
        let manifestPub = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()

        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: wrongSig,
                                  pinnedKeyBase64: nil, manifestKeyBase64: manifestPub, requireSignature: false),
            .signatureInvalid)
    }

}
