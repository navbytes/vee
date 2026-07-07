import XCTest
import CryptoKit
@testable import VeeCatalog

final class StoreIntegrityTests: XCTestCase {
    private let source = "#!/bin/bash\necho hi\n"

    // MARK: - Hash pinning

    func testMatchingHashPasses() {
        let hash = PluginHash.sha256Hex(source)
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: hash, signatureBase64: nil, signingKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    func testWrongHashFails() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: "deadbeef", signatureBase64: nil, signingKeyBase64: nil, requireSignature: false),
            .hashMismatch
        )
    }

    func testHashIsCaseInsensitive() {
        let hash = PluginHash.sha256Hex(source).uppercased()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: hash, signatureBase64: nil, signingKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    func testNoHashSkipsHashCheck() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: nil, signingKeyBase64: nil, requireSignature: false),
            .ok
        )
    }

    // MARK: - Signatures

    private func sign(_ source: String, key: Curve25519.Signing.PrivateKey) -> String {
        let digest = Data(SHA256.hash(data: Data(source.utf8)))
        return try! key.signature(for: digest).base64EncodedString()
    }

    func testValidSignaturePasses() {
        let key = Curve25519.Signing.PrivateKey()
        let sig = sign(source, key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, signingKeyBase64: pub, requireSignature: true),
            .ok
        )
    }

    func testSignatureOverDifferentSourceFails() {
        let key = Curve25519.Signing.PrivateKey()
        let sig = sign("something else", key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, signingKeyBase64: pub, requireSignature: true),
            .signatureInvalid
        )
    }

    func testWrongKeyFails() {
        let key = Curve25519.Signing.PrivateKey()
        let sig = sign(source, key: key)
        let otherPub = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, signingKeyBase64: otherPub, requireSignature: true),
            .signatureInvalid
        )
    }

    func testRequiredSignatureMissingFails() {
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: nil, signingKeyBase64: nil, requireSignature: true),
            .signatureMissing
        )
    }

    func testUnrequiredButPresentSignatureStillValidated() {
        // A wrong signature fails even when the store doesn't require signing.
        let key = Curve25519.Signing.PrivateKey()
        let sig = sign("tampered", key: key)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(
            StoreIntegrity.verify(source: source, declaredSHA256: nil, signatureBase64: sig, signingKeyBase64: pub, requireSignature: false),
            .signatureInvalid
        )
    }

    // MARK: - Convenience over entry + store

    func testConvenienceResolvesPinnedKeyOverManifest() {
        let key = Curve25519.Signing.PrivateKey()
        let sig = sign(source, key: key)
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
}
