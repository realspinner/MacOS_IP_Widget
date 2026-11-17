import Foundation

/// DB-IP Country Lite; compact, sorted 10-byte IPv4 range records.
public actor LocalGeoIP {
    public static let shared = LocalGeoIP()
    private var database: Data
    private var updating = false
    private var lastAttempt = Date.distantPast
    private let cache: URL

    public init() {
        cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPWidget/GeoIP/country.bin")
        #if SWIFT_PACKAGE
        let bundled = Bundle.module.url(forResource: "country", withExtension: "bin", subdirectory: "Resources")
        #else
        let bundled = Bundle.main.url(forResource: "country", withExtension: "bin")
        #endif
        let saved = try? Data(contentsOf: cache)
        database = saved.flatMap { Self.valid($0) ? $0 : nil }
            ?? bundled.flatMap { try? Data(contentsOf: $0) } ?? Data()
    }

    static func valid(_ data: Data) -> Bool {
        guard data.count >= 10, data.count % 10 == 0 else { return false }
        var previous: UInt32?
        for offset in stride(from: 0, to: data.count, by: 10) {
            let start = number(data, offset), end = number(data, offset + 4)
            guard start <= end, previous.map({ start > $0 }) ?? true,
                  data[offset+8...offset+9].allSatisfy({ (65...90).contains($0) }) else { return false }
            previous = end
        }
        return true
    }

    private static func number(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<offset+4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public func country(for ip: IPv4Address) -> String? {
        var low = 0, high = database.count / 10
        while low < high {
            let mid = (low + high) / 2, offset = mid * 10
            if ip.rawValue < Self.number(database, offset) { high = mid }
            else if ip.rawValue > Self.number(database, offset + 4) { low = mid + 1 }
            else { return String(data: database[offset+8..<offset+10], encoding: .ascii) }
        }
        return nil
    }

    /// Check daily; download a new monthly edition without blocking IP detection.
    public func updateIfNeeded(now: Date = Date()) async {
        let attemptKey = "geoIPLastUpdateAttempt"
        let savedAttempt = UserDefaults.standard.object(forKey: attemptKey) as? Date ?? .distantPast
        guard !Task.isCancelled, !updating,
              now.timeIntervalSince(max(lastAttempt, savedAttempt)) > 86400 else { return }
        updating = true
        lastAttempt = now
        UserDefaults.standard.set(now, forKey: attemptKey)
        defer { updating = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: now)
        let marker = cache.deletingPathExtension().appendingPathExtension("month")
        if (try? String(contentsOf: marker, encoding: .utf8)) == month { return }
        if !FileManager.default.fileExists(atPath: cache.path), month == "2026-11" { return }
        do {
            let url = URL(string: "https://download.db-ip.com/free/dbip-country-lite-\(month).csv.gz")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = false
            configuration.allowsExpensiveNetworkAccess = false
            configuration.allowsConstrainedNetworkAccess = false
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (file, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size < 20_000_000 else { return }
            // Decompression and parsing must not block country lookups on this actor.
            let worker = Task.detached(priority: .utility) {
                try Self.readArchive(file)
            }
            let compact = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard compact.count > 100_000, Self.valid(compact) else { return }
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try compact.write(to: cache, options: .atomic)
            database = compact
            try month.write(to: marker, atomically: true, encoding: .utf8)
        } catch { /* Keep last known good edition, retry tomorrow. */ }
    }

    /// Stream decompressed rows with bounded memory instead of loading the full CSV.
    static func readArchive(_ file: URL) throws -> Data {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", file.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Only the child owns the writer now, so EOF is observable on the reader.
        try pipe.fileHandleForWriting.close()
        defer {
            try? pipe.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        var pending = Data()
        var result = Data()
        var expandedBytes = 0
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            expandedBytes += chunk.count
            guard expandedBytes <= 64 * 1024 * 1024 else { throw TwoIPError.invalidResponse }
            pending.append(chunk)
            var start = pending.startIndex
            while let newline = pending[start...].firstIndex(of: 10) {
                let row = pending[start..<newline]
                guard row.count <= 1024, let text = String(data: row, encoding: .utf8) else {
                    throw TwoIPError.invalidResponse
                }
                result.append(compact(text))
                start = pending.index(after: newline)
            }
            pending = Data(pending[start...])
            guard pending.count <= 1024 else { throw TwoIPError.invalidResponse }
        }
        if !pending.isEmpty {
            guard let text = String(data: pending, encoding: .utf8) else { throw TwoIPError.invalidResponse }
            result.append(compact(text))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TwoIPError.invalidResponse }
        return result
    }

    static func compact(_ csv: String) -> Data {
        var result = Data()
        for line in csv.split(whereSeparator: \.isNewline) {
            let fields = line.replacingOccurrences(of: "\"", with: "").split(separator: ",")
            guard fields.count == 3, !fields[0].contains(":") else { continue }
            guard let start = IPv4Address(canonicalizing: String(fields[0])),
                  let end = IPv4Address(canonicalizing: String(fields[1])), fields[2].utf8.count == 2 else { return Data() }
            for value in [start.rawValue, end.rawValue] {
                result.append(contentsOf: [24,16,8,0].map { UInt8(truncatingIfNeeded: value >> $0) })
            }
            result.append(contentsOf: fields[2].utf8)
        }
        return result
    }
}
