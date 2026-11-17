import Foundation

/// Synthetic reputation, not the probability of access to any particular service.
public struct IPRating: Codable, Equatable, Sendable {
    public let ip: IPv4Address
    public let percent: Int
    public let isVPNOrProxy: Bool

    public init(ip: IPv4Address, risk: Int, vpn: Bool, proxy: Bool, hosting: Bool, tor: Bool, compromised: Bool) {
        self.ip = ip
        // Use the strongest classification penalty to avoid counting a VPN's
        // hosting/proxy classifications more than once.
        let penalty = max(compromised ? 30 : 0, tor ? 25 : 0,
                          proxy ? 20 : 0, vpn ? 15 : 0, hosting ? 10 : 0)
        percent = max(0, min(100, 100 - Int((Double(max(0, min(100, risk))) * 0.7).rounded()) - penalty))
        isVPNOrProxy = vpn || proxy || tor
    }
}

public protocol IPRatingServicing: Sendable {
    func rating(for ip: IPv4Address) async throws -> IPRating
}

public actor IPRatingClient: IPRatingServicing {
    private let session: URLSession
    private struct Cached: Codable, Sendable {
        let date: Date
        let rating: IPRating
    }
    private var cache: [String: Cached] = [:]
    private let cacheURL: URL?
    private var retryAfter = Date.distantPast

    public init(session: URLSession? = nil, cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? (session == nil ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dev.spinner.ipwidget/ip-ratings.json") : nil)
        if let url = self.cacheURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Cached].self, from: data) {
            self.cache = saved.filter { Date().timeIntervalSince($0.value.date) >= 0 && Date().timeIntervalSince($0.value.date) < 86400 }
        }
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 12
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    public func rating(for ip: IPv4Address) async throws -> IPRating {
        guard ip.isPublic else { throw TwoIPError.invalidResponse }
        if let entry = cache[ip.description], Date().timeIntervalSince(entry.date) >= 0,
           Date().timeIntervalSince(entry.date) < 86400, entry.rating.ip == ip { return entry.rating }
        guard Date() >= retryAfter else { throw TwoIPError.rateLimited(until: retryAfter) }
        // v2 remains supported by the provider until 2035; explicitly request
        // VPN, ASN/network classification and risk fields.
        let url = URL(string: "https://proxycheck.io/v2/\(ip)?vpn=1&asn=1&risk=1&tag=0")!
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw TwoIPError.invalidResponse }
        guard response.statusCode == 200 else {
            if response.statusCode == 429 { retryAfter = Date().addingTimeInterval(3600) }
            throw TwoIPError.httpStatus(response.statusCode)
        }
        let result = try Self.parse(data, ip: ip)
        if cache.count >= 64 { cache.removeAll() }
        cache[ip.description] = Cached(date: Date(), rating: result)
        if let url = cacheURL, let data = try? JSONEncoder().encode(cache) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return result
    }

    public static func parse(_ data: Data, ip: IPv4Address) throws -> IPRating {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["status"] as? String, ["ok", "warning"].contains(status),
              let entry = root[ip.description] as? [String: Any],
              let proxy = entry["proxy"] as? String, ["yes", "no"].contains(proxy),
              let risk = entry["risk"] as? Int, (0...100).contains(risk),
              let type = entry["type"] as? String else { throw TwoIPError.invalidResponse }
        let kind = type.lowercased()
        let vpn = kind.contains("vpn")
        return IPRating(ip: ip, risk: risk, vpn: vpn,
                        proxy: proxy == "yes" && !vpn,
                        hosting: kind.contains("hosting"), tor: kind.contains("tor"),
                        compromised: kind.contains("compromised"))
    }
}
