import Testing
@testable import IPWidgetCore

@Suite("Route fingerprint")
struct RouteFingerprintTests {
    @Test func summaryNamesInterfaceAndGateway() {
        let fingerprint = RouteFingerprint(
            primaryService: "service-1",
            router: "192.168.1.1",
            interfaceName: "en0"
        )
        #expect(fingerprint.summary == "en0 · 192.168.1.1")
    }

    @Test func summaryHandlesMissingValues() {
        #expect(RouteFingerprint().summary == "? · no router")
    }

    @Test func equalityTracksAllRouteComponents() {
        let base = RouteFingerprint(
            primaryService: "A",
            router: "10.0.0.1",
            interfaceName: "en0",
            ipv6Service: ""
        )
        #expect(base == RouteFingerprint(
            primaryService: "A",
            router: "10.0.0.1",
            interfaceName: "en0"
        ))
        #expect(base != RouteFingerprint(
            primaryService: "B",
            router: "10.0.0.1",
            interfaceName: "en0"
        ))
        #expect(base != RouteFingerprint(
            primaryService: "A",
            router: "10.0.0.2",
            interfaceName: "en0"
        ))
        #expect(base != RouteFingerprint(
            primaryService: "A",
            router: "10.0.0.1",
            interfaceName: "en5"
        ))
    }
}
