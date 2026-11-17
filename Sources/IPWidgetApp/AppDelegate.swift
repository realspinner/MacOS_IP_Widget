import AppKit
import Combine
import IPWidgetCore
import IPWidgetUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = ConnectionModel(service: MultiIPClient())
    private var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let defaults = UserDefaults.standard
    private let summaryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "", action: nil, keyEquivalent: "r")
    private let addWidgetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        let coordinator = AppCoordinator(model: model)
        self.coordinator = coordinator
        subscribeToModel()
        coordinator.start()
        refreshUI()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            WidgetRegistration.ensureWidgetEnabled()
            self?.coordinator?.refreshNow()
        }

        if !defaults.bool(forKey: "didShowAddWidgetHelp") {
            defaults.set(true, forKey: "didShowAddWidgetHelp")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.showAddWidgetHelp()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionItem = NSMenuItem(title: "IP Widget \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        refreshItem.target = self
        refreshItem.action = #selector(refreshNow)
        menu.addItem(refreshItem)

        addWidgetItem.title = L10n.t(.addWidgetMenu)
        addWidgetItem.target = self
        addWidgetItem.action = #selector(showAddWidgetHelp)
        menu.addItem(addWidgetItem)

        loginItem.title = L10n.t(.launchAtLogin)
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: L10n.t(.openSite),
            action: #selector(openSite),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let attribution = NSMenuItem(title: "IP Geolocation by DB-IP (CC BY 4.0)", action: #selector(openGeoIPAttribution), keyEquivalent: "")
        attribution.target = self
        menu.addItem(attribution)

        quitItem.title = L10n.t(.quit)
        quitItem.target = self
        quitItem.action = #selector(quit)
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openGeoIPAttribution() {
        NSWorkspace.shared.open(URL(string: "https://db-ip.com/db/download/ip-to-country-lite")!)
    }

    private func subscribeToModel() {
        model.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshUI()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshUI() {
        let summary: String
        let symbol: String
        switch model.status {
        case .loading:
            summary = L10n.t(.statusChecking)
            symbol = "globe"
        case .online(let geo):
            summary = "\(geo.ip.description) · \(geo.localizedCountryName())"
            symbol = "globe"
        case .unavailable(.noConnection):
            summary = L10n.t(.noConnection)
            symbol = "exclamationmark.triangle.fill"
        case .unavailable(.serviceUnavailable):
            summary = L10n.t(.serviceUnavailable)
            symbol = "exclamationmark.triangle.fill"
        }

        summaryItem.title = summary
        refreshItem.title = L10n.t(.refreshNow)
        refreshItem.isEnabled = !model.isRefreshing
        addWidgetItem.title = L10n.t(.addWidgetMenu)
        loginItem.title = L10n.t(.launchAtLogin)
        quitItem.title = L10n.t(.quit)

        if LoginItem.isEnabled {
            loginItem.state = .on
        } else if LoginItem.isPendingApproval {
            loginItem.state = .mixed
        } else {
            loginItem.state = .off
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "IP Widget"
        )?.withSymbolConfiguration(configuration)
        statusItem?.button?.contentTintColor = model.status.isOnline ? nil : .systemRed
        statusItem?.button?.toolTip = summary
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        coordinator?.refreshNow()
    }

    @objc private func showAddWidgetHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.t(.addWidgetTitle)
        alert.informativeText = L10n.t(.addWidgetMessage)
        alert.addButton(withTitle: L10n.t(.ok))
        alert.runModal()
    }

    @objc private func toggleLoginItem() {
        if LoginItem.isPendingApproval {
            presentLoginItemApproval()
            return
        }
        let enable = !LoginItem.isEnabled
        do {
            try LoginItem.setEnabled(enable)
            if enable && LoginItem.isPendingApproval {
                presentLoginItemApproval()
            }
        } catch {
            presentLoginItemError(error)
        }
        refreshUI()
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(URL(string: "https://2ip.io/")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentLoginItemApproval() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.t(.loginItemApprovalTitle)
        alert.informativeText = L10n.t(.loginItemApprovalMessage)
        alert.addButton(withTitle: L10n.t(.openSettings))
        alert.addButton(withTitle: L10n.t(.cancel))
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItem.openSystemSettings()
        }
    }

    private func presentLoginItemError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.loginItemFailedTitle)
        alert.informativeText = L10n.t(.loginItemFailedMessage) + "\n\n" + error.localizedDescription
        alert.addButton(withTitle: L10n.t(.openSettings))
        alert.addButton(withTitle: L10n.t(.cancel))
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItem.openSystemSettings()
        }
    }
}
