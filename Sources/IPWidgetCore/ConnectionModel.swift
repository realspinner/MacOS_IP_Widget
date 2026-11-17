import Combine
import Foundation
import os

/// Holds everything the widget renders and decides what a network event means.
///
/// The model deliberately knows nothing about timers, windows or AppKit, which
/// keeps the interesting state transitions unit-testable.
@MainActor
public final class ConnectionModel: ObservableObject {
    @Published public private(set) var rating: IPRating?
    @Published public private(set) var status: WidgetStatus
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var interfaceName: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?
    public private(set) var retryAfter: Date?
    public private(set) var lastCheckedAt: Date?

    private let ratingService: any IPRatingServicing
    private let service: any TwoIPServicing
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "connection")
    private var path: NetworkPathStatus
    private var generation = 0

    public init(
        service: any TwoIPServicing,
        ratingService: any IPRatingServicing = IPRatingClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        initialStatus: WidgetStatus = .loading,
        initialPath: NetworkPathStatus = .unknown
    ) {
        self.service = service
        self.ratingService = ratingService
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
            rating = nil
            isRefreshing = false
            lastCheckedAt = now()
            status = .unavailable(.noConnection)
            lastError = nil
            logger.debug("default route is unavailable")
            return
        }

        if !wasSatisfied && status != .updating {
            // The route came back: show the spinner until the new query finishes.
            status = .loading
            logger.debug("default route is available on \(newPath.interfaceName ?? "unknown", privacy: .public)")
        }
    }

    /// Publishes the transition immediately and invalidates the old route's result.
    public func beginNetworkUpdate() {
        generation &+= 1
        rating = nil
        isRefreshing = false
        status = .updating
        lastCheckedAt = now()
        lastError = nil
    }

    public func networkDidChange(preferredProvider: IPProvider? = nil) async {
        if let preferredProvider { await service.setPreferredProvider(preferredProvider) }
        await service.networkDidChange()
    }

    /// Fetches fresh data, returning nil when skipped, cancelled, or unsuccessful.
    @discardableResult
    public func refresh(forNetworkTransition: Bool = false) async -> GeoInfo? {
        guard path.isSatisfied else {
            lastCheckedAt = now()
            status = .unavailable(.noConnection)
            return nil
        }
        guard !isRefreshing else { return nil }

        isRefreshing = true
        let requestGeneration = generation
        defer {
            if requestGeneration == generation {
                isRefreshing = false
            }
        }

        do {
            let geo: GeoInfo
            if forNetworkTransition {
                geo = try await service.currentGeoForNetworkTransition()
            } else {
                geo = try await service.currentGeo()
            }
            try Task.checkCancellation()

            guard requestGeneration == generation, path.isSatisfied else { return nil }

            retryAfter = nil
            lastCheckedAt = now()
            if rating?.ip != geo.ip { rating = nil }
            status = .online(geo)
            lastUpdated = now()
            lastError = nil
            logger.debug("external IPv4 resolved, country \(geo.countryCode ?? "--", privacy: .public)")
            return geo
        } catch is CancellationError {
            return nil
        } catch {
            if let twoIPError = error as? TwoIPError, twoIPError == .cancelled {
                return nil
            }
            guard requestGeneration == generation else { return nil }
            if case .rateLimited(let until) = error as? TwoIPError {
                retryAfter = until
            } else {
                retryAfter = nil
            }
            lastCheckedAt = now()
            lastError = String(describing: error)
            rating = nil
            status = .unavailable(path.isSatisfied ? .serviceUnavailable : .noConnection)
            logger.error("refresh failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
    /// Called by the coordinator only after stabilization and a successful IP query.
    public func refreshRating() async {
        guard path.isSatisfied, case .online(let geo) = status else { return }
        let requestGeneration = generation
        rating = nil
        do {
            let result = try await ratingService.rating(for: geo.ip)
            try Task.checkCancellation()
            guard requestGeneration == generation, path.isSatisfied,
                  case .online(let current) = status, current.ip == result.ip else { return }
            rating = result
        } catch {
            // Missing data never becomes a fabricated zero or a connection error.
            logger.debug("IP rating unavailable")
        }
    }

}
