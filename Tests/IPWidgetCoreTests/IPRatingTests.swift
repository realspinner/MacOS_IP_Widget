import Foundation
import Testing
@testable import IPWidgetCore

private let ratingIP = IPv4Address(rawValue: 0x08080808)

@Test func ratingFormulaUsesStrongestPenalty() {
    #expect(IPRating(ip: ratingIP, risk: 0, vpn: false, proxy: false, hosting: false, tor: false, compromised: false).percent == 100)
    let vpn = IPRating(ip: ratingIP, risk: 73, vpn: true, proxy: false, hosting: true, tor: false, compromised: false)
    #expect(vpn.percent == 34)
    #expect(vpn.isVPNOrProxy)
    #expect(IPRating(ip: ratingIP, risk: 100, vpn: true, proxy: true, hosting: true, tor: true, compromised: true).percent == 0)
}

@Test func ratingRejectsMissingRiskOrWrongIP() throws {
    let valid = Data(#"{"status":"ok","8.8.8.8":{"proxy":"yes","type":"VPN","risk":73}}"#.utf8)
    #expect(try IPRatingClient.parse(valid, ip: ratingIP).percent == 34)
    for json in [
        #"{"status":"ok","8.8.8.8":{"proxy":"no","type":"Residential"}}"#,
        #"{"status":"denied"}"#,
        #"{"status":"ok","1.1.1.1":{"proxy":"no","type":"Residential","risk":0}}"#
    ] {
        #expect(throws: (any Error).self) { try IPRatingClient.parse(Data(json.utf8), ip: ratingIP) }
    }
}

private actor RatingProbe: IPRatingServicing {
    private var requests = 0
    func rating(for ip: IPv4Address) async throws -> IPRating {
        requests += 1
        return IPRating(ip: ip, risk: 0, vpn: false, proxy: false, hosting: false, tor: false, compromised: false)
    }
    func count() -> Int { requests }
}
private struct RatingGeoService: TwoIPServicing {
    func currentGeo() async throws -> GeoInfo { GeoInfo(ip: ratingIP) }
}

@Test @MainActor func ratingRequiresSuccessfulIPAndExplicitPostStabilizationCall() async {
    let probe = RatingProbe()
    let model = ConnectionModel(service: RatingGeoService(), ratingService: probe)
    await model.refreshRating()
    #expect(await probe.count() == 0)
    model.apply(path: NetworkPathStatus(isSatisfied: true, interfaceName: "en0"))
    model.beginNetworkUpdate()
    await model.refreshRating()
    #expect(await probe.count() == 0)
    await model.refresh(forNetworkTransition: true)
    #expect(await probe.count() == 0)
    await model.refreshRating()
    #expect(model.rating?.percent == 100)
    model.beginNetworkUpdate()
    #expect(model.rating == nil)
}

private struct PersistedRatingFixture: Codable {
    let date: Date
    let rating: IPRating
}

@Test func ratingCacheSurvivesRestartForOneDay() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("ratings.json")
    let expected = IPRating(ip: ratingIP, risk: 73, vpn: true, proxy: false, hosting: true, tor: false, compromised: false)
    let entries = [ratingIP.description: PersistedRatingFixture(date: Date().addingTimeInterval(-23 * 3600), rating: expected)]
    try JSONEncoder().encode(entries).write(to: url)
    // An unusable network makes this fail if the persisted 23-hour cache is ignored.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 1,
                                                "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 1]
    let client = IPRatingClient(session: URLSession(configuration: configuration), cacheURL: url)
    #expect(try await client.rating(for: ratingIP) == expected)
    let restarted = IPRatingClient(session: URLSession(configuration: configuration), cacheURL: url)
    #expect(try await restarted.rating(for: ratingIP) == expected)
}

private actor DelayedRating: IPRatingServicing {
    private var gate: CheckedContinuation<IPRating, Never>?
    func rating(for ip: IPv4Address) async throws -> IPRating {
        await withCheckedContinuation { gate = $0 }
    }
    func started() -> Bool { gate != nil }
    func release() {
        gate?.resume(returning: IPRating(ip: ratingIP, risk: 0, vpn: false, proxy: false, hosting: false, tor: false, compromised: false))
        gate = nil
    }
}

@Test @MainActor func lateRatingIsDiscardedAfterNetworkChange() async {
    let service = DelayedRating()
    let model = ConnectionModel(service: RatingGeoService(), ratingService: service)
    await model.refresh()
    let task = Task { await model.refreshRating() }
    while !(await service.started()) { await Task.yield() }
    model.beginNetworkUpdate()
    await service.release()
    await task.value
    #expect(model.rating == nil)
    #expect(model.status == .updating)
}
