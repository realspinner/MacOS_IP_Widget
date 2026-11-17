import Foundation

public enum UnavailableReason: String, Codable, Equatable, Sendable {
    case appNotRunning
    case noConnection
    case serviceUnavailable
}

public enum WidgetStatus: Codable, Equatable, Sendable {
    case updating
    case loading
    case online(GeoInfo)
    case unavailable(UnavailableReason)

    public var geo: GeoInfo? {
        if case .online(let geo) = self { return geo }
        return nil
    }

    public var isOnline: Bool {
        geo != nil
    }
}
