import Foundation
import os

/// Maps a 2ip.io query to the state the widget displays.
public enum WidgetSnapshotLoader {
    private static let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "widget-network")
    public static func status(using service: any TwoIPServicing) async -> WidgetStatus {
        do {
            return .online(try await service.currentGeo())
        } catch let error as TwoIPError {
            logger.error("widget refresh failed: \(String(describing: error), privacy: .public)")
            return .unavailable(error == .offline ? .noConnection : .serviceUnavailable)
        } catch {
            logger.error("widget refresh failed: \(String(describing: error), privacy: .public)")
            return .unavailable(.serviceUnavailable)
        }
    }
}
