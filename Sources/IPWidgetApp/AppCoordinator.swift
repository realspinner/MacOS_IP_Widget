import AppKit
import Foundation
import IPWidgetCore
import WidgetKit
import os

/// Wires the default-route monitor, the five-minute timer and the model together,
/// and asks WidgetKit to refresh the desktop widget whenever something changes.
@MainActor
final class AppCoordinator {
    static let refreshInterval: TimeInterval = 4 * 60

    private let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "route")
    private let model: ConnectionModel
    private let monitor = NetworkPathMonitor()
    private var routeMonitor: RouteMonitor?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var databaseTask: Task<Void, Never>?
    private var lastWidgetReload = Date.distantPast
    private var widgetReloadTask: Task<Void, Never>?
    private var rateLimitRetryTask: Task<Void, Never>?
    private var lastPath: NetworkPathStatus?
    private var isRunning = false
    private var isStabilizing = false

    init(model: ConnectionModel) {
        self.model = model
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        monitor.start { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handle(path: path)
            }
        }

        let routeMonitor = RouteMonitor { [weak self] fingerprint in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(fingerprint)
            }
        }
        self.routeMonitor = routeMonitor
        routeMonitor.start()

        let timer = Timer(timeInterval: Self.refreshInterval + Double.random(in: -15...15), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isStabilizing else { return }
                self.refreshNow()
            }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Timers do not fire while the Mac is asleep, so refresh after waking.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stabilizeNetwork()
            }
        }

        // The first NWPathMonitor callback initiates the first IP check.
        updateDatabaseIfNeeded()
    }

    func stop() {
        isRunning = false
        isStabilizing = false
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        rateLimitRetryTask?.cancel()
        rateLimitRetryTask = nil
        widgetReloadTask?.cancel()
        widgetReloadTask = nil
        databaseTask?.cancel()
        databaseTask = nil
        monitor.cancel()
        routeMonitor?.stop()
        routeMonitor = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    func refreshNow() {
        guard isRunning, lastPath != nil, !isStabilizing else { return }
        let previous = refreshTask
        previous?.cancel()
        let model = model
        refreshTask = Task { @MainActor [weak self] in
            // Let the cancelled request clear isRefreshing before starting again.
            await previous?.value
            guard !Task.isCancelled else { return }
            let geo = await model.refresh()
            guard !Task.isCancelled else { return }
            self?.reloadWidget()
            if geo != nil { await model.refreshRating() }
            guard !Task.isCancelled else { return }
            self?.reloadWidget()
            self?.scheduleRateLimitRetry()
        }
        updateDatabaseIfNeeded()
    }

    private func updateDatabaseIfNeeded() {
        guard isRunning, databaseTask == nil else { return }
        databaseTask = Task(priority: .utility) { @MainActor [weak self] in
            await LocalGeoIP.shared.updateIfNeeded()
            self?.databaseTask = nil
        }
    }

    private func handle(path: NetworkPathStatus) {
        guard isRunning, path != lastPath else { return }
        lastPath = path
        logger.debug(
            "path update: satisfied=\(path.isSatisfied, privacy: .public) interface=\(path.interfaceName ?? "-", privacy: .public)"
        )
        model.apply(path: path)
        // Probe even after a disconnect: some VPNs reconnect without another
        // distinct path snapshot. Each attempt reads the monitor's current path.
        stabilizeNetwork()
    }

    private func handleRouteChange(_ fingerprint: RouteFingerprint) {
        guard isRunning else { return }
        logger.debug("default route changed: \(fingerprint.summary, privacy: .public)")
        stabilizeNetwork()
    }

    func changePreferredProvider(_ provider: IPProvider) {
        stabilizeNetwork(preferredProvider: provider)
    }

    private func stabilizeNetwork(preferredProvider: IPProvider? = nil) {
        guard isRunning else { return }
        isStabilizing = true
        rateLimitRetryTask?.cancel()
        rateLimitRetryTask = nil
        let previous = refreshTask
        previous?.cancel()
        model.beginNetworkUpdate()
        reloadWidget()
        let model = model
        let monitor = monitor
        refreshTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await model.networkDidChange(preferredProvider: preferredProvider ?? IPProvider.saved)
            guard !Task.isCancelled else { return }
            var publishedStatus = model.status
            let resolved = await NetworkStabilizer.run { [weak self] in
                guard !Task.isCancelled else { return nil }
                model.apply(path: monitor.currentStatus)
                let geo = await model.refresh(forNetworkTransition: true)
                guard !Task.isCancelled else { return nil }
                // Publish changed results; successful responses need no confirmations.
                if model.status != publishedStatus {
                    publishedStatus = model.status
                    self?.reloadWidget()
                }
                if let until = model.retryAfter { throw TwoIPError.rateLimited(until: until) }
                return geo?.ip
            }
            guard !Task.isCancelled else { return }
            self?.isStabilizing = false
            self?.reloadWidget()
            if resolved {
                await model.refreshRating()
                guard !Task.isCancelled else { return }
                self?.reloadWidget()
            }
            self?.logger.debug("network transition check finished: resolved=\(resolved, privacy: .public)")
        }
    }

    private func scheduleRateLimitRetry() {
        guard isRunning, let until = model.retryAfter else { return }
        rateLimitRetryTask?.cancel()
        let delay = max(1, until.timeIntervalSinceNow + 1)
        rateLimitRetryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            self?.rateLimitRetryTask = nil
            self?.refreshNow()
        }
    }

    private func reloadWidget() {
        guard isRunning else { return }
        // Publish before requesting a timeline; coalescing must not drop file updates.
        if let checkedAt = model.lastCheckedAt {
            do {
                try SharedWidgetStore.standard().write(SharedWidgetSnapshot(
                    checkedAt: checkedAt, lastUpdated: model.lastUpdated,
                    status: model.status, interfaceName: model.interfaceName, rating: model.rating))
            } catch {
                logger.error("could not write shared widget snapshot: \(String(describing: error), privacy: .public)")
            }
        }
        guard widgetReloadTask == nil else { return }
        let remaining = max(0, 0.5 - Date().timeIntervalSince(lastWidgetReload))
        if remaining == 0 {
            performWidgetReload()
        } else {
            // Preserve the trailing reload: dropping it can leave an error card
            // visible even after the companion has successfully resolved the IP.
            widgetReloadTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
                self?.widgetReloadTask = nil
                self?.performWidgetReload()
            }
        }
    }

    private func performWidgetReload() {
        guard isRunning else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: IPWidgetConstants.kind)
    }
}
