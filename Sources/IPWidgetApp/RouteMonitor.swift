import Foundation
import IPWidgetCore
import os
import SystemConfiguration

/// Watches the system's dynamic store for changes to the default route.
///
/// `NWPathMonitor` reports availability/interface-set changes, but a switch of
/// the default route between two healthy interfaces (Wi-Fi ↔ Ethernet, VPN)
/// does not always produce a path update. The global IPv4/IPv6 keys in the
/// dynamic store do change in that case.
final class RouteMonitor: @unchecked Sendable {
    private let logger = Logger(subsystem: "dev.spinner.ipwidget", category: "route")
    private let queue = DispatchQueue(label: "dev.spinner.ipwidget.route-monitor", qos: .utility)
    private let onChange: @Sendable (RouteFingerprint) -> Void
    private let lock = NSLock()

    private var store: SCDynamicStore?
    private var fallbackTimer: DispatchSourceTimer?
    private var lastFingerprint: RouteFingerprint?

    init(onChange: @escaping @Sendable (RouteFingerprint) -> Void) {
        self.onChange = onChange

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        store = SCDynamicStoreCreate(
            nil,
            "IPWidgetRouteMonitor" as CFString,
            routeMonitorCallback,
            &context
        )
    }

    deinit {
        stop()
    }

    func start() {
        guard fallbackTimer == nil else { return }
        guard let store else {
            logger.error("could not create SCDynamicStore")
            return
        }

        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
        ] as CFArray
        let patterns = [
            "State:/Network/Service/.*/IPv4",
            "State:/Network/Service/.*/IPv6",
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/IPv6",
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns) else {
            logger.error("could not register dynamic store notifications")
            return
        }
        guard SCDynamicStoreSetDispatchQueue(store, queue) else {
            logger.error("could not attach dynamic store dispatch queue")
            return
        }

        let fingerprint = currentFingerprint()
        lock.lock()
        lastFingerprint = fingerprint
        lock.unlock()
        logger.debug("route monitor started: \(fingerprint.summary, privacy: .public)")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Notifications handle changes immediately; polling is only a safety net.
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            self?.checkFallback()
        }
        timer.resume()
        fallbackTimer = timer
    }

    func stop() {
        fallbackTimer?.cancel()
        fallbackTimer = nil
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
    }

    fileprivate func handleDynamicStoreChange(changedKeys: CFArray?) {
        let keys = (changedKeys as? [String]) ?? []
        let relevant = keys.isEmpty || keys.contains { key in
            (key.contains("/IPv4") || key.contains("/IPv6")) && !key.contains("/DNS")
        }
        guard relevant else { return }

        let fingerprint = currentFingerprint()
        lock.lock()
        lastFingerprint = fingerprint
        lock.unlock()

        logger.debug(
            "dynamic store changed: \(fingerprint.summary, privacy: .public) keys=\(keys.joined(separator: ","), privacy: .public)"
        )
        onChange(fingerprint)
    }

    private func checkFallback() {
        let fingerprint = currentFingerprint()

        lock.lock()
        let changed = lastFingerprint != nil && lastFingerprint != fingerprint
        lastFingerprint = fingerprint
        lock.unlock()

        guard changed else { return }
        logger.debug("route fingerprint changed (fallback): \(fingerprint.summary, privacy: .public)")
        onChange(fingerprint)
    }

    private func currentFingerprint() -> RouteFingerprint {
        let ipv4 = dictionary(for: "State:/Network/Global/IPv4")
        let ipv6 = dictionary(for: "State:/Network/Global/IPv6")

        return RouteFingerprint(
            primaryService: ipv4["PrimaryService"] as? String ?? "",
            router: ipv4["Router"] as? String ?? "",
            interfaceName: ipv4["PrimaryInterface"] as? String ?? "",
            ipv6Service: ipv6["PrimaryService"] as? String ?? ""
        )
    }

    private func dictionary(for key: String) -> [String: Any] {
        guard let store,
              let value = SCDynamicStoreCopyValue(store, key as CFString)
        else {
            return [:]
        }
        return value as? [String: Any] ?? [:]
    }
}

private func routeMonitorCallback(
    store: SCDynamicStore?,
    changedKeys: CFArray?,
    info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let monitor = Unmanaged<RouteMonitor>.fromOpaque(info).takeUnretainedValue()
    monitor.handleDynamicStoreChange(changedKeys: changedKeys)
}
