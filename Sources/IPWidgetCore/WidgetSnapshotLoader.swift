import Foundation

/// Maps a 2ip.io query to the state the widget displays.
public enum WidgetSnapshotLoader {
    public static func status(using service: any TwoIPServicing) async -> WidgetStatus {
        do {
            return .online(try await service.currentGeo())
        } catch let error as TwoIPError {
            return .unavailable(error == .offline ? .noConnection : .serviceUnavailable)
        } catch {
            return .unavailable(.serviceUnavailable)
        }
    }
}
