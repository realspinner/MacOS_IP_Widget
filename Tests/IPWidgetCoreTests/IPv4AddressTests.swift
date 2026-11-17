import Testing
@testable import IPWidgetCore

@Suite("IPv4 addresses")
struct IPv4AddressTests {
    @Test func canonicalizesWhitespaceAndTrailingNewline() {
        let address = IPv4Address(canonicalizing: "  45.159.12.7\n")
        #expect(address?.description == "45.159.12.7")
    }

    @Test func stripsLeadingZeroes() {
        #expect(IPv4Address(canonicalizing: "045.159.012.007")?.description == "45.159.12.7")
        #expect(IPv4Address(canonicalizing: "0.0.0.0")?.description == "0.0.0.0")
        #expect(IPv4Address(canonicalizing: "255.255.255.255")?.description == "255.255.255.255")
    }

    @Test func rejectsMalformedValues() {
        let invalid = [
            "",
            "   ",
            "1.2.3",
            "1.2.3.4.5",
            "1.2.3.",
            ".1.2.3.4",
            "1..3.4",
            "1.2.3.256",
            "1.2.3.-1",
            "1.2.3.+4",
            "1.2. 3.4",
            "1.2.3.4/24",
            "1.2.3.4:80",
            "::1",
            "2001:db8::1",
            "1.2.3.٤",
            "one.two.three.four",
            "1.2.3.4\n5.6.7.8",
        ]
        for value in invalid {
            #expect(IPv4Address(canonicalizing: value) == nil, "should reject \(value.debugDescription)")
        }
    }

    @Test func equalityAndOrderingUseTheNumericValue() throws {
        let a = try #require(IPv4Address(canonicalizing: "010.0.0.1"))
        let b = try #require(IPv4Address(canonicalizing: "10.0.0.1"))
        let lower = try #require(IPv4Address(canonicalizing: "9.255.255.255"))
        let higher = try #require(IPv4Address(canonicalizing: "10.0.0.2"))
        #expect(a == b)
        #expect(lower < a)
        #expect(a < higher)
    }

    @Test func addressClassification() throws {
        let ten = try #require(IPv4Address(canonicalizing: "10.1.2.3"))
        let lowerPrivate = try #require(IPv4Address(canonicalizing: "172.16.0.1"))
        let upperPrivate = try #require(IPv4Address(canonicalizing: "172.31.255.254"))
        let justOutsidePrivate = try #require(IPv4Address(canonicalizing: "172.32.0.1"))
        let lan = try #require(IPv4Address(canonicalizing: "192.168.1.1"))
        let loopback = try #require(IPv4Address(canonicalizing: "127.0.0.1"))
        let linkLocal = try #require(IPv4Address(canonicalizing: "169.254.1.1"))
        let publicAddress = try #require(IPv4Address(canonicalizing: "45.159.12.7"))

        #expect(ten.isPrivate)
        #expect(lowerPrivate.isPrivate)
        #expect(upperPrivate.isPrivate)
        #expect(!justOutsidePrivate.isPrivate)
        #expect(lan.isPrivate)
        #expect(loopback.isLoopback)
        #expect(linkLocal.isLinkLocal)
        #expect(publicAddress.isPublic)
        #expect(!lan.isPublic)
    }
}
