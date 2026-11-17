import Combine
import Foundation
import os

/// Holds everything the widget renders and decides what a network event means.
///
/// The model deliberately knows nothing about timers, windows or AppKit, which
/// keeps the interesting state transitions unit-testable.
@MainActor
public final class ConnectionModel: ObservableObject {
    @Published public private(set) var status: WidgetStatus
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var interfaceName: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?

    private let service: any TwoIPServicing
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "connection")
    private var path: NetworkPathStatus
    private var generation = 0

    public init(
        service: any TwoIPServicing,
        now: @escaping @Sendable () -> Date = { Date() },
        initialStatus: WidgetStatus = .loading,
        initialPath: NetworkPathStatus = .unknown
    ) {
        self.service = service
        self.now = now
        self.status = initialStatus
        self.path = initialPath
    }

    /// Applies a default-route change. Losing the path immediately switches the
    /// widget to the warning state and invalidates any in-flight request.
    public func apply(path newPath: NetworkPathStatus) {
        let wasSatisfied = path.isSatisfied
        path = newPath
        interfaceName = newPath.interfaceName

        if !newPath.isSatisfied {
            generation &+= 1
            isRefreshing = false
            status = .unavailable(.noConnection)
            lastError = nil
            logger.debug("default route is unavailable")
            return
        }

        if !wasSatisfied {
            // The route came back: show the spinner until the new query finishes.
            status = .loading
            logger.debug("default route is available on \(newPath.interfaceName ?? "unknown", privacy: .public)")
        }
    }

    /// Queries `2ip.io` for the external IPv4 address and its country.
    public func refresh() async {
        guard path.isSatisfied else {
            status = .unavailable(.noConnection)
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        let requestGeneration = generation
        defer {
            if requestGeneration == generation {
                isRefreshing = false
            }
        }

        do {
            let geo = try await service.currentGeo()
            try Task.checkCancellation()

            guard requestGeneration == generation, path.isSatisfied else { return }

            status = .online(geo)
            lastUpdated = now()
            lastError = nil
            logger.debug("external IPv4 resolved, country \(geo.countryCode ?? "--", privacy: .public)")
        } catch is CancellationError {
            return
        } catch {
            if let twoIPError = error as? TwoIPError, twoIPError == .cancelled {
                return
            }
            guard requestGeneration == generation else { return }
            lastError = String(describing: error)
            status = .unavailable(path.isSatisfied ? .serviceUnavailable : .noConnection)
            logger.error("refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}
