import Foundation

/// Rotates independent IP reflectors; uses a local country database when needed.
public actor MultiIPClient: TwoIPServicing {
    private let session: URLSession
    private var next: Int
    private var cooldown: [Int: Date] = [:]
    private var failures: [Int: Int] = [:]
    private let endpoints = ["https://api.2ip.io/", "https://api.ipify.org?format=json", "https://checkip.amazonaws.com/"]

    public init(session: URLSession? = nil, startIndex: Int? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = session ?? URLSession(configuration: config)
        next = ((startIndex ?? Int.random(in: 0..<3)) % 3 + 3) % 3
    }

    public func currentGeo() async throws -> GeoInfo {
        Task { await LocalGeoIP.shared.updateIfNeeded() }
        let start = next
        next = (next + 1) % endpoints.count
        var lastError: Error = TwoIPError.invalidResponse
        for step in 0..<endpoints.count {
            try Task.checkCancellation()
            let index = (start + step) % endpoints.count
            if let until = cooldown[index], until > Date() { continue }
            do {
                var request = URLRequest(url: URL(string: endpoints[index])!)
                request.timeoutInterval = 4
                request.setValue("IPWidget/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw TwoIPError.invalidResponse }
                guard http.statusCode == 200 else { throw TwoIPError.httpStatus(http.statusCode) }
                let geo: GeoInfo
                if index == 2 {
                    guard let text = String(data: data, encoding: .utf8), let ip = IPv4Address(canonicalizing: text) else { throw TwoIPError.invalidResponse }
                    geo = GeoInfo(ip: ip)
                } else { geo = try TwoIPClient.parseGeo(data) }
                guard geo.ip.isPublic else { throw TwoIPError.invalidResponse }
                failures[index] = 0
                cooldown[index] = nil
                let localCountry = await LocalGeoIP.shared.country(for: geo.ip)
                let country = geo.countryCode ?? localCountry
                return GeoInfo(ip: geo.ip, countryCode: country, countryName: geo.countryName)
            } catch {
                if Task.isCancelled { throw TwoIPError.cancelled }
                lastError = error
                let count = min((failures[index] ?? 0) + 1, 6)
                failures[index] = count
                cooldown[index] = Date().addingTimeInterval(min(3600, 60 * pow(2, Double(count - 1))))
            }
        }
        if let error = lastError as? URLError, error.code == .notConnectedToInternet { throw TwoIPError.offline }
        throw TwoIPError.transport("IP services are unavailable")
    }
}
