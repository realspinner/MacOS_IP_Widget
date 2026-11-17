import Foundation
import Testing
@testable import IPWidgetCore

private actor MockTwoIPService: TwoIPServicing {
    private let result: Result<GeoInfo, TwoIPError>
    private let delay: Duration?
    private var requestCount = 0

    init(geo: GeoInfo, delay: Duration? = nil) {
        self.result = .success(geo)
        self.delay = delay
    }

    init(error: TwoIPError, delay: Duration? = nil) {
        self.result = .failure(error)
        self.delay = delay
    }

    func currentGeo() async throws -> GeoInfo {
        requestCount += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
        switch result {
        case .success(let geo):
            return geo
        case .failure(let error):
            throw error
        }
    }

    func numberOfRequests() -> Int {
        requestCount
    }
}

/// Suspends the first request until the test releases it, so a path change can
/// be injected while the request is in flight.
private actor GatedService: TwoIPServicing {
    private let geo: GeoInfo
    private var gate: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(geo: GeoInfo) {
        self.geo = geo
    }

    func currentGeo() async throws -> GeoInfo {
        if let started {
            self.started = nil
            started.resume()
        }
        await withCheckedContinuation { continuation in
            gate = continuation
        }
        return geo
    }

    func waitUntilStarted() async {
        if gate != nil { return }
        await withCheckedContinuation { continuation in
            started = continuation
        }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
@Suite("Connection model", .serialized)
struct ConnectionModelTests {
    private let ip = IPv4Address(canonicalizing: "45.159.12.7")!
    private var geo: GeoInfo {
        GeoInfo(ip: ip, countryCode: "SE", countryName: "Sweden")
    }
    private let connected = NetworkPathStatus(
        isSatisfied: true,
        interfaceName: "en0",
        interfaceType: "Wi-Fi"
    )

    private func makeModel(service: any TwoIPServicing, now: Date? = nil) -> ConnectionModel {
        if let now {
            return ConnectionModel(service: service, now: { now })
        }
        return ConnectionModel(service: service)
    }

    @Test func initialStateIsLoading() {
        let model = makeModel(service: MockTwoIPService(geo: geo))
        #expect(model.status == .loading)
        #expect(model.lastUpdated == nil)
        #expect(!model.isRefreshing)
    }

    @Test func successfulRefreshPublishesGeoAndTimestamp() async {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let service = MockTwoIPService(geo: geo)
        let model = makeModel(service: service, now: fixed)

        model.apply(path: connected)
        await model.refresh()

        #expect(model.status == .online(geo))
        #expect(model.lastUpdated == fixed)
        #expect(model.interfaceName == "en0")
        #expect(!model.isRefreshing)
        #expect(model.lastError == nil)
    }

    @Test func losingThePathImmediatelyShowsWarning() async {
        let service = MockTwoIPService(geo: geo)
        let model = makeModel(service: service)
        model.apply(path: connected)
        await model.refresh()
        #expect(model.status.isOnline)

        model.apply(path: NetworkPathStatus(isSatisfied: false))

        #expect(model.status == .unavailable(.noConnection))
        #expect(!model.isRefreshing)
    }

    @Test func refreshWithoutAPathDoesNotCallTheService() async {
        let service = MockTwoIPService(geo: geo)
        let model = makeModel(service: service)
        model.apply(path: NetworkPathStatus(isSatisfied: false))

        await model.refresh()

        #expect(model.status == .unavailable(.noConnection))
        let requests = await service.numberOfRequests()
        #expect(requests == 0)
    }

    @Test func serviceFailureWhileConnectedShowsServiceWarning() async {
        let service = MockTwoIPService(error: .httpStatus(503))
        let model = makeModel(service: service)
        model.apply(path: connected)

        await model.refresh()

        #expect(model.status == .unavailable(.serviceUnavailable))
        #expect(model.lastError != nil)
        #expect(model.lastUpdated == nil)
        #expect(!model.isRefreshing)
    }

    @Test func reconnectingShowsLoadingAndThenData() async {
        let service = MockTwoIPService(geo: geo)
        let model = makeModel(service: service)

        model.apply(path: NetworkPathStatus(isSatisfied: false))
        #expect(model.status == .unavailable(.noConnection))

        model.apply(path: connected)
        #expect(model.status == .loading)

        await model.refresh()
        #expect(model.status == .online(geo))
    }

    @Test func interfaceSwitchKeepsExistingDataUntilRefreshed() async {
        let service = MockTwoIPService(geo: geo)
        let model = makeModel(service: service)
        model.apply(path: connected)
        await model.refresh()

        let ethernet = NetworkPathStatus(
            isSatisfied: true,
            interfaceName: "en5",
            interfaceType: "Ethernet"
        )
        model.apply(path: ethernet)

        #expect(model.status == .online(geo))
        #expect(model.interfaceName == "en5")
    }

    @Test func concurrentRefreshesAreCoalesced() async {
        let service = MockTwoIPService(geo: geo, delay: .milliseconds(120))
        let model = makeModel(service: service)
        model.apply(path: connected)

        let first = Task { await model.refresh() }
        let second = Task { await model.refresh() }
        await first.value
        await second.value

        let requests = await service.numberOfRequests()
        #expect(requests == 1)
        #expect(model.status == .online(geo))
    }

    @Test func resultArrivingAfterPathLossIsIgnored() async {
        let service = GatedService(geo: geo)
        let model = makeModel(service: service)
        model.apply(path: connected)

        let refresh = Task { await model.refresh() }
        await service.waitUntilStarted()

        model.apply(path: NetworkPathStatus(isSatisfied: false))
        await service.release()
        await refresh.value

        #expect(model.status == .unavailable(.noConnection))
        #expect(!model.isRefreshing)
    }

    @Test func cancellingTheTaskLeavesStateUntouched() async {
        let service = MockTwoIPService(geo: geo, delay: .seconds(5))
        let model = makeModel(service: service)
        model.apply(path: connected)

        let refresh = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(40))
        refresh.cancel()
        await refresh.value

        #expect(model.status == .loading)
        #expect(!model.isRefreshing)
    }

    @Test func widgetLoaderMapsSuccess() async {
        let status = await WidgetSnapshotLoader.status(using: MockTwoIPService(geo: geo))
        #expect(status == .online(geo))
    }

    @Test func widgetLoaderMapsOfflineError() async {
        let status = await WidgetSnapshotLoader.status(using: MockTwoIPService(error: .offline))
        #expect(status == .unavailable(.noConnection))
    }

    @Test func widgetLoaderMapsServiceError() async {
        let status = await WidgetSnapshotLoader.status(using: MockTwoIPService(error: .httpStatus(503)))
        #expect(status == .unavailable(.serviceUnavailable))
    }

    @Test func widgetLoaderMapsTransportError() async {
        let status = await WidgetSnapshotLoader.status(using: MockTwoIPService(error: .transport("timeout")))
        #expect(status == .unavailable(.serviceUnavailable))
    }
}
