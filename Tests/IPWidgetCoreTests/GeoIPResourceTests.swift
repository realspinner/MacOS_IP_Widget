import Foundation
import Testing
@testable import IPWidgetCore

@Suite("GeoIP resource bounds")
struct GeoIPResourceTests {
    private func withArchive(_ text: String, check: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let csv = directory.appendingPathComponent("country.csv")
        try text.write(to: csv, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = [csv.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        try check(csv.appendingPathExtension("gz"))
    }

    @Test func streamsRowsAcrossChunksAndHandlesFinalRowWithoutNewline() throws {
        let row = "1.0.0.0,1.0.0.255,AU\n"
        let csv = String(repeating: row, count: 5000) + "1.0.1.0,1.0.1.255,CN"
        try withArchive(csv) { archive in
            let actual = try LocalGeoIP.readArchive(archive)
            #expect(actual == LocalGeoIP.compact(csv))
        }
    }

    @Test func rejectsOversizedRows() throws {
        try withArchive(String(repeating: "x", count: 2048)) { archive in
            #expect(throws: TwoIPError.invalidResponse) {
                try LocalGeoIP.readArchive(archive)
            }
        }
    }

    @Test func rejectsCorruptArchive() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid gzip".utf8).write(to: file)
        #expect(throws: TwoIPError.invalidResponse) {
            try LocalGeoIP.readArchive(file)
        }
    }

    @Test func cancellationStopsArchiveConversion() async throws {
        let task = Task {
            try withArchive("1.0.0.0,1.0.0.255,AU\n") { archive in
                withUnsafeCurrentTask { $0?.cancel() }
                #expect(throws: CancellationError.self) {
                    try LocalGeoIP.readArchive(archive)
                }
            }
        }
        try await task.value
    }
}
