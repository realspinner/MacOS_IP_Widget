import AppKit
import Foundation
import IPWidgetCore
import WidgetKit
import os

/// Wires the default-route monitor, the five-minute timer and the model together,
/// and asks WidgetKit to refresh the desktop widget whenever something changes.
@MainActor
final class AppCoordinator {
    static let refreshInterval: TimeInterval = IPWidgetConstants.refreshInterval
    static let pathChangeDelay: Duration = .seconds(1.2)

    private let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "route")
    private let model: ConnectionModel
    private let monitor = NetworkPathMonitor()
    private var routeMonitor: RouteMonitor?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(model: ConnectionModel) {
        self.model = model
    }

    func start() {
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

        let timer = Timer(timeInterval: Self.refreshInterval + Double.random(in: -30...30), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Timers do not fire while the Mac is asleep, so refresh after waking.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadWidget()
                self?.scheduleRefresh(after: .seconds(2))
            }
        }

        refreshNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        debounceTask?.cancel()
        monitor.cancel()
        routeMonitor?.stop()
        routeMonitor = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    func refreshNow() {
        debounceTask?.cancel()
        debounceTask = nil
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.model.refresh()
            self.reloadWidget()
        }
    }

    private func handle(path: NetworkPathStatus) {
        logger.debug(
            "path update: satisfied=\(path.isSatisfied, privacy: .public) interface=\(path.interfaceName ?? "-", privacy: .public)"
        )
        model.apply(path: path)
        reloadWidget()
        guard path.isSatisfied else { return }
        // Give DHCP/route setup a moment before querying 2ip.io.
        scheduleRefresh(after: Self.pathChangeDelay)
    }

    private func handleRouteChange(_ fingerprint: RouteFingerprint) {
        logger.debug("default route changed: \(fingerprint.summary, privacy: .public)")
        reloadWidget()
        scheduleRefresh(after: .milliseconds(900))
    }

    private func scheduleRefresh(after delay: Duration) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: IPWidgetConstants.kind)
    }
}
