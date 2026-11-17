import Foundation
import Network

/// A value snapshot of the system's default network path.
public struct NetworkPathStatus: Equatable, Sendable {
    public var isSatisfied: Bool
    public var isIPv4Available: Bool
    public var isExpensive: Bool
    public var interfaceName: String?
    public var interfaceType: String?

    public init(
        isSatisfied: Bool,
        isIPv4Available: Bool = true,
        isExpensive: Bool = false,
        interfaceName: String? = nil,
        interfaceType: String? = nil
    ) {
        self.isSatisfied = isSatisfied
        self.isIPv4Available = isIPv4Available
        self.isExpensive = isExpensive
        self.interfaceName = interfaceName
        self.interfaceType = interfaceType
    }

    /// Used before the first path update arrives; allows an initial attempt.
    public static let unknown = NetworkPathStatus(isSatisfied: true)

    public init(path: NWPath) {
        self.isSatisfied = path.status == .satisfied
        self.isIPv4Available = path.supportsIPv4
        self.isExpensive = path.isExpensive

        let preferred = path.availableInterfaces.first
        self.interfaceName = preferred?.name
        self.interfaceType = preferred.map { interfaceTypeName($0.type) }
    }
}

private func interfaceTypeName(_ type: NWInterface.InterfaceType) -> String {
    switch type {
    case .wifi: return "Wi-Fi"
    case .wiredEthernet: return "Ethernet"
    case .cellular: return "Cellular"
    case .loopback: return "Loopback"
    case .other: return "Other"
    @unknown default: return "Other"
    }
}

/// Watches the default route and reports every change (interface up/down,
/// Wi-Fi to Ethernet switches, VPN, etc.).
public final class NetworkPathMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.spinner.ipwidget.path-monitor", qos: .utility)

    public init() {}

    public func start(handler: @escaping @Sendable (NetworkPathStatus) -> Void) {
        monitor.pathUpdateHandler = { path in
            handler(NetworkPathStatus(path: path))
        }
        monitor.start(queue: queue)
    }

    public func cancel() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
