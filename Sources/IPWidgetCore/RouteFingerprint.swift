import Foundation

/// The parts of `State:/Network/Global/IPv4` / `IPv6` that identify the current
/// default route. Used to detect changes that `NWPathMonitor` can miss when two
/// interfaces are both up.
public struct RouteFingerprint: Equatable, Sendable {
    public let primaryService: String
    public let router: String
    public let interfaceName: String
    public let ipv6Service: String

    public init(
        primaryService: String = "",
        router: String = "",
        interfaceName: String = "",
        ipv6Service: String = ""
    ) {
        self.primaryService = primaryService
        self.router = router
        self.interfaceName = interfaceName
        self.ipv6Service = ipv6Service
    }

    public static let empty = RouteFingerprint()

    public var summary: String {
        let interface = interfaceName.isEmpty ? "?" : interfaceName
        let gateway = router.isEmpty ? "no router" : router
        return "\(interface) · \(gateway)"
    }
}
