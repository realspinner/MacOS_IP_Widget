import Foundation

public enum TwoIPError: Error, Equatable, Sendable {
    /// The request never reached the server because there is no usable connection.
    case offline
    case httpStatus(Int)
    case rateLimited(until: Date)
    case invalidResponse
    case cancelled
    case transport(String)
}

extension TwoIPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline:
            return "No internet connection"
        case .rateLimited(let until):
            return "2ip.io rate limit; retry after \(until)"
        case .httpStatus(let code):
            return "2ip.io returned HTTP \(code)"
        case .invalidResponse:
            return "Unexpected response from 2ip.io"
        case .cancelled:
            return "Request cancelled"
        case .transport(let message):
            return message
        }
    }
}

public protocol TwoIPServicing: Sendable {
    func setPreferredProvider(_ provider: IPProvider) async
    func networkDidChange() async
    func currentGeoForNetworkTransition() async throws -> GeoInfo

    /// The external IPv4 address of the current default route, together with
    /// the country that 2ip.io associates with it.
    func currentGeo() async throws -> GeoInfo
}

public extension TwoIPServicing {
    func setPreferredProvider(_ provider: IPProvider) async {}
    func networkDidChange() async {}
    func currentGeoForNetworkTransition() async throws -> GeoInfo {
        try await currentGeo()
    }
}

/// Client for the 2ip.io JSON API.
///
/// `GET https://api.2ip.io/` answers with the caller's external IPv4 address,
/// country name and ISO code in one atomic response:
///
/// ```json
/// {"ip":"45.159.12.7","country":"Sweden","code":"SE","emoji":"🇸🇪"}
/// ```
///
/// The plain `https://2ip.io/` page is intentionally not used: it rejects
/// requests from custom user agents with an HTML "loading" page.
public final class TwoIPClient: TwoIPServicing {
    public static let apiEndpoint = URL(string: "https://api.2ip.io/")!

    private let session: URLSession
    private let ownsSession: Bool

    public init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    deinit {
        if ownsSession { session.invalidateAndCancel() }
    }

    public func currentGeo() async throws -> GeoInfo {
        let data = try await get(Self.apiEndpoint)
        return try Self.parseGeo(data)
    }

    // MARK: - Parsing (public so the behavior is directly testable)

    public static func parseGeo(_ data: Data) throws -> GeoInfo {
        guard let payload = try? JSONDecoder().decode(GeoPayload.self, from: data),
              let rawIP = payload.ip,
              let address = IPv4Address(canonicalizing: rawIP)
        else {
            throw TwoIPError.invalidResponse
        }

        return GeoInfo(
            ip: address,
            countryCode: payload.code,
            countryName: payload.country
        )
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("IPWidget/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TwoIPError.invalidResponse
            }
            guard http.statusCode == 200 else {
                throw TwoIPError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as TwoIPError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw TwoIPError.cancelled
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                throw TwoIPError.offline
            default:
                throw TwoIPError.transport(error.localizedDescription)
            }
        } catch is CancellationError {
            throw TwoIPError.cancelled
        } catch {
            throw TwoIPError.transport(error.localizedDescription)
        }
    }

    private struct GeoPayload: Decodable {
        let ip: String?
        let country: String?
        let code: String?
    }
}
