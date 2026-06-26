import XCTest
@testable import VeeEngine

/// R2-MED-5 (docs/AUDIT-2.md): `isBlockedNetworkHost(_:)` was a naive `hasPrefix`
/// string match that (a) missed the obfuscated IPv4 forms a resolver/`connect(2)`
/// still maps to a blocked address, and (b) over-blocked legitimate hostnames
/// (`fc-data.com`). This suite asserts the rewritten classifier blocks each
/// bypass form and no longer over-blocks real names.
///
/// New file (per the build rules) so the existing engine suites are untouched.
final class SSRFClassifierTests: XCTestCase {

    // MARK: - Canonical literals still blocked (no regression)

    func testCanonicalLoopbackAndPrivateRangesBlocked() {
        for h in ["127.0.0.1", "127.1.2.3", "10.0.0.1", "192.168.1.1",
                  "172.16.0.1", "172.31.255.255", "169.254.169.254",
                  "0.0.0.0", "localhost", "db.localhost"] {
            XCTAssertTrue(isBlockedNetworkHost(h), "\(h) must be blocked")
        }
    }

    func testCanonicalIPv6LoopbackLinkLocalAndUlaBlocked() {
        for h in ["::1", "[::1]", "fe80::1", "[fe80::abcd]",
                  "fc00::1", "fd12:3456:789a::1", "[fd00::1]"] {
            XCTAssertTrue(isBlockedNetworkHost(h), "\(h) must be blocked")
        }
    }

    func testPublicAddressesAndRangeBoundariesNotBlocked() {
        // 172.15/172.32 are OUTSIDE the 172.16/12 private block; 8.8.8.8 and a
        // normal hostname are public.
        for h in ["8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1",
                  "example.com", "api.github.com", "2606:4700:4700::1111"] {
            XCTAssertFalse(isBlockedNetworkHost(h), "\(h) must NOT be blocked")
        }
    }

    // MARK: - Obfuscated IPv4: decimal (R2-MED-5 bypass)

    /// `2130706433` == 0x7F000001 == 127.0.0.1. A bare 32-bit decimal integer host
    /// resolves to loopback via `inet_aton`, so it must be blocked.
    func testDecimalIntegerLoopbackBypassBlocked() {
        XCTAssertTrue(isBlockedNetworkHost("2130706433"), "decimal 127.0.0.1 must be blocked")
        // 169.254.169.254 == 0xA9FEA9FE == 2852039166 (cloud metadata).
        XCTAssertTrue(isBlockedNetworkHost("2852039166"), "decimal link-local metadata IP must be blocked")
    }

    // MARK: - Obfuscated IPv4: hex / octal (R2-MED-5 bypass)

    /// `0x7f.0.0.1` (hex first octet) and `0x7f000001` (single hex word) and
    /// `0177.0.0.1` (octal first octet) all resolve to 127.0.0.1 via `inet_aton`.
    func testHexAndOctalLoopbackBypassesBlocked() {
        for h in ["0x7f.0.0.1", "0x7f000001", "0177.0.0.1", "0x7F.0.0.1"] {
            XCTAssertTrue(isBlockedNetworkHost(h), "\(h) resolves to loopback and must be blocked")
        }
    }

    /// Short forms (fewer than four parts) that `inet_aton` expands: `127.1` →
    /// 127.0.0.1, `10.1` → 10.0.0.1.
    func testShortFormPrivateBypassesBlocked() {
        XCTAssertTrue(isBlockedNetworkHost("127.1"), "127.1 expands to loopback")
        XCTAssertTrue(isBlockedNetworkHost("10.1"), "10.1 expands to a private address")
    }

    // MARK: - Obfuscated IPv6: IPv4-mapped (R2-MED-5 bypass)

    /// `[::ffff:169.254.169.254]` is an IPv4-mapped IPv6 literal wrapping the cloud
    /// metadata IP; it must be unwrapped and blocked. Likewise loopback/private.
    func testIPv4MappedIPv6BypassesBlocked() {
        for h in ["[::ffff:169.254.169.254]", "::ffff:169.254.169.254",
                  "[::ffff:127.0.0.1]", "::ffff:10.0.0.1", "[::ffff:192.168.0.1]"] {
            XCTAssertTrue(isBlockedNetworkHost(h), "\(h) maps to a blocked IPv4 and must be blocked")
        }
    }

    /// An IPv4-mapped IPv6 wrapping a PUBLIC address is not blocked (the unwrap
    /// classifies the real embedded address, it doesn't blanket-block mapped form).
    func testIPv4MappedPublicNotBlocked() {
        XCTAssertFalse(isBlockedNetworkHost("[::ffff:8.8.8.8]"), "mapped public IP must NOT be blocked")
    }

    // MARK: - Over-block fix: real hostnames starting fc/fd (R2-MED-5)

    /// The old `hasPrefix("fc")/("fd")` wrongly blocked legitimate hostnames. A
    /// real DNS name that merely starts with `fc`/`fd` is NOT an IPv6 literal and
    /// must pass this defense-in-depth layer (the allowlist governs it).
    func testHostnamesStartingFcFdNotOverBlocked() {
        for h in ["fc-data.com", "fd-cdn.net", "fconline.example",
                  "fdisk.io", "fe.example.com", "fec0ffee.dev"] {
            XCTAssertFalse(isBlockedNetworkHost(h), "\(h) is a hostname, not an IPv6 literal — must NOT be blocked")
        }
    }

    /// Sanity: the fix is specific to the parse step — an ACTUAL `fc00::/7` IPv6
    /// literal is still blocked (we didn't throw the baby out with the bathwater).
    func testRealUlaLiteralStillBlockedAfterOverblockFix() {
        XCTAssertTrue(isBlockedNetworkHost("fc00::1"))
        XCTAssertTrue(isBlockedNetworkHost("fd00:dead:beef::1"))
    }
}
