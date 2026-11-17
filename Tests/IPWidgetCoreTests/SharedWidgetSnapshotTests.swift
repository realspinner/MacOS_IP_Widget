import Foundation
import Testing
@testable import IPWidgetCore

@Suite("Shared widget snapshot")
struct SharedWidgetSnapshotTests {
    private let checked = Date(timeIntervalSince1970: 1_700_000_000)
    private var geo: GeoInfo {
        GeoInfo(ip: IPv4Address(rawValue: 0x08080808), countryCode: "US", countryName: "United States")
    }
    private func snapshot(_ status: WidgetStatus) -> SharedWidgetSnapshot {
        SharedWidgetSnapshot(checkedAt: checked, lastUpdated: checked, status: status, interfaceName: "en0")
    }

    @Test func expiresOnlyAfterFiveMinutes() {
        let value = snapshot(.online(geo))
        #expect(value.displayStatus(at: checked.addingTimeInterval(299)) == .online(geo))
        #expect(value.displayStatus(at: checked.addingTimeInterval(300)) == .online(geo))
        #expect(value.displayStatus(at: checked.addingTimeInterval(300.001)) == .unavailable(.appNotRunning))
    }

    @Test func rejectsFutureTimestampsAndNonpublicAddresses() {
        #expect(snapshot(.online(geo)).displayStatus(at: checked.addingTimeInterval(-60)) == .unavailable(.appNotRunning))
        let local = GeoInfo(ip: IPv4Address(rawValue: 0x7F000001))
        #expect(snapshot(.online(local)).displayStatus(at: checked) == .unavailable(.appNotRunning))
    }

    @Test func failuresAlsoExpire() {
        for status in [WidgetStatus.unavailable(.noConnection), .unavailable(.serviceUnavailable)] {
            #expect(snapshot(status).displayStatus(at: checked) == status)
            #expect(snapshot(status).displayStatus(at: checked.addingTimeInterval(301)) == .unavailable(.appNotRunning))
        }
    }

    @Test func atomicRoundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedWidgetStore(url: directory.appendingPathComponent("snapshot.json"))
        for status in [WidgetStatus.online(geo), .loading, .updating, .unavailable(.noConnection), .unavailable(.serviceUnavailable)] {
            let expected = snapshot(status)
            try store.write(expected)
            let actual = try store.read()
            #expect(actual == expected)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func missingCorruptAndOversizedFilesAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SharedWidgetStore(url: directory.appendingPathComponent("snapshot.json"))
        #expect(throws: (any Error).self) { try store.read() }
        try Data("invalid JSON".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.read() }
        try Data(repeating: 0, count: 16385).write(to: store.url)
        #expect(throws: (any Error).self) { try store.read() }
    }
}
