import XCTest
import AppKit
import VeePluginFormat
@testable import VeeMenu

/// Covers the `SymbolImageFactory` render cache (wave 1a): identical inputs
/// must return the same `NSImage` instance, and anything that would change the
/// rendered pixels must produce a distinct instance.
@MainActor
final class SymbolImageCacheTests: XCTestCase {
    /// The smallest possible valid PNG: a 1x1 transparent pixel.
    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    func testSameSFSymbolParamsReturnIdenticalInstance() {
        var params = LineParams()
        params.swiftbar.sfimage = "star"
        params.swiftbar.sfsize = 14
        params.swiftbar.sfcolor = [.named("red")]

        let first = SymbolImageFactory.image(for: params)
        let second = SymbolImageFactory.image(for: params)
        XCTAssertNotNil(first)
        XCTAssertIdentical(first, second)
    }

    func testDifferentSFSizeProducesDifferentInstance() {
        var a = LineParams()
        a.swiftbar.sfimage = "gear"
        a.swiftbar.sfsize = 10
        var b = a
        b.swiftbar.sfsize = 20

        let imageA = SymbolImageFactory.image(for: a)
        let imageB = SymbolImageFactory.image(for: b)
        XCTAssertNotNil(imageA)
        XCTAssertNotNil(imageB)
        XCTAssertNotIdentical(imageA, imageB)
    }

    func testDifferentSFConfigProducesDifferentInstance() {
        var a = LineParams()
        a.swiftbar.sfimage = "bolt"
        a.swiftbar.sfconfig = #"{"weight":"bold"}"#
        var b = a
        b.swiftbar.sfconfig = #"{"weight":"light"}"#

        let imageA = SymbolImageFactory.image(for: a)
        let imageB = SymbolImageFactory.image(for: b)
        XCTAssertNotNil(imageA)
        XCTAssertNotNil(imageB)
        XCTAssertNotIdentical(imageA, imageB)
    }

    func testDifferentSFColorProducesDifferentInstance() {
        var a = LineParams()
        a.swiftbar.sfimage = "flame"
        a.swiftbar.sfcolor = [.named("red")]
        var b = a
        b.swiftbar.sfcolor = [.named("blue")]

        let imageA = SymbolImageFactory.image(for: a)
        let imageB = SymbolImageFactory.image(for: b)
        XCTAssertNotNil(imageA)
        XCTAssertNotNil(imageB)
        XCTAssertNotIdentical(imageA, imageB)
    }

    func testTemplateAndPlainBase64OfSamePayloadAreDistinctInstances() {
        var templateParams = LineParams()
        templateParams.templateImage = Self.tinyPNGBase64
        var plainParams = LineParams()
        plainParams.image = Self.tinyPNGBase64

        let templateImage = SymbolImageFactory.image(for: templateParams)
        let plainImage = SymbolImageFactory.image(for: plainParams)

        XCTAssertNotNil(templateImage)
        XCTAssertNotNil(plainImage)
        XCTAssertNotIdentical(templateImage, plainImage)
        XCTAssertEqual(templateImage?.isTemplate, true)
        XCTAssertEqual(plainImage?.isTemplate, false)
    }

    func testSameBase64ImageTwiceReturnsIdenticalInstance() {
        var params = LineParams()
        params.image = Self.tinyPNGBase64

        let first = SymbolImageFactory.image(for: params)
        let second = SymbolImageFactory.image(for: params)
        XCTAssertNotNil(first)
        XCTAssertIdentical(first, second)
    }
}
