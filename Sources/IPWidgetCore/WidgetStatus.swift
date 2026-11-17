import Foundation

public enum UnavailableReason: Equatable, Sendable {
    case noConnection
    case serviceUnavailable
}

public enum WidgetStatus: Equatable, Sendable {
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
