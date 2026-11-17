import Foundation

/// Tries the preferred provider first, with local country lookup for plain IPv4 results.
public actor MultiIPClient: TwoIPServicing {
    private var session: URLSession
    private let ownsSession: Bool
    private var rateLimitedUntil: [IPProvider: Date] = [:]
    private var preferredProvider: IPProvider
    private var cooldown: [IPProvider: Date] = [:]
    private var failures: [IPProvider: Int] = [:]

    public init(session: URLSession? = nil, startIndex: Int? = nil, preferredProvider: IPProvider = .twoIP) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration: config)
        ownsSession = session == nil
        self.preferredProvider = startIndex == 1 ? .icanhazip : preferredProvider
    }

    deinit {
        if ownsSession { session.invalidateAndCancel() }
    }

    public func networkDidChange() async {
        cooldown.removeAll()
        failures.removeAll()
        if ownsSession {
            // Do not reuse a keep-alive connection established through the old VPN.
            let previous = session
            session = URLSession(configuration: previous.configuration)
            previous.invalidateAndCancel()
        }
    }

    public func setPreferredProvider(_ provider: IPProvider) async {
        preferredProvider = provider
    }

    public func nextAllowedRequestDate() -> Date? {
        let dates = IPProvider.allCases.compactMap { rateLimitedUntil[$0] }.filter { $0 > Date() }
        return dates.count == IPProvider.allCases.count ? dates.min() : nil
    }

    public func currentGeo() async throws -> GeoInfo {
        try await resolve(transition: false)
    }

    public func currentGeoForNetworkTransition() async throws -> GeoInfo {
        try await resolve(transition: true)
    }

    private func resolve(transition: Bool) async throws -> GeoInfo {
        try Task.checkCancellation()
        let providers = [preferredProvider] + IPProvider.allCases.filter { $0 != preferredProvider }
        var lastError: Error = TwoIPError.invalidResponse
        for provider in providers {
            try Task.checkCancellation()
            if let until = rateLimitedUntil[provider], until > Date() {
                lastError = TwoIPError.rateLimited(until: until)
                continue
            }
            // Settled transition checks bypass transient transport failures,
            // but never bypass a provider's explicit Retry-After.
            if !transition, let until = cooldown[provider], until > Date() { continue }
            do {
                var request = URLRequest(url: provider.endpoint)
                request.timeoutInterval = 4
                request.setValue("IPWidget/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
                request.setValue((provider == .twoIP ? "application/json" : "text/plain"), forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw TwoIPError.invalidResponse }
                if http.statusCode == 429 {
                    let until = Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"))
                    rateLimitedUntil[provider] = until
                    throw TwoIPError.rateLimited(until: until)
                }
                guard http.statusCode == 200 else { throw TwoIPError.httpStatus(http.statusCode) }
                let geo: GeoInfo
                if provider == .twoIP {
                    geo = try TwoIPClient.parseGeo(data)
                } else {
                    guard let text = String(data: data, encoding: .utf8),
                          let ip = IPv4Address(canonicalizing: text), ip.isPublic else {
                        throw TwoIPError.invalidResponse
                    }
                    geo = GeoInfo(ip: ip)
                }
                guard geo.ip.isPublic else { throw TwoIPError.invalidResponse }
                rateLimitedUntil[provider] = nil
                failures[provider] = 0
                cooldown[provider] = nil
                let country: String?
                if let code = geo.countryCode {
                    country = code
                } else {
                    country = await LocalGeoIP.shared.country(for: geo.ip)
                }
                return GeoInfo(ip: geo.ip, countryCode: country, countryName: geo.countryName)
            } catch {
                if Task.isCancelled { throw TwoIPError.cancelled }
                lastError = error
                let count = min((failures[provider] ?? 0) + 1, 6)
                failures[provider] = count
                cooldown[provider] = Date().addingTimeInterval(min(3600, 60 * pow(2, Double(count - 1))))
            }
        }
        if let until = nextAllowedRequestDate() { throw TwoIPError.rateLimited(until: until) }
        if let error = lastError as? URLError, error.code == .notConnectedToInternet { throw TwoIPError.offline }
        if let error = lastError as? TwoIPError { throw error }
        throw TwoIPError.transport(lastError.localizedDescription)
    }

    static func retryDate(_ header: String?, now: Date = Date()) -> Date {
        if let header, let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite {
            return now.addingTimeInterval(max(1, seconds))
        }
        if let header {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header), date > now { return date }
        }
        return now.addingTimeInterval(60)
    }

}
