import Foundation
import Testing
@testable import IPWidgetCore

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("2ip.io client", .serialized)
struct TwoIPClientTests {
    private func makeClient() -> TwoIPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TwoIPClient(session: URLSession(configuration: configuration))
    }

    private func response(_ request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
    }

    private let swedenJSON = """
    {
      "ip": "45.159.12.7",
      "city": "Stockholm",
      "country": "Sweden",
      "code": "SE",
      "emoji": "🇸🇪",
      "asn": {"id": 212238, "name": "CDNEXT", "hosting": false}
    }
    """

    @Test func fetchesAddressAndCountryInOneRequest() async throws {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.handler = { request in
            (try self.response(request), Data(self.swedenJSON.utf8))
        }

        let geo = try await makeClient().currentGeo()

        #expect(geo.ip.description == "45.159.12.7")
        #expect(geo.countryCode == "SE")
        #expect(geo.countryName == "Sweden")
        #expect(geo.flag == "🇸🇪")
        #expect(StubURLProtocol.lastRequest?.url?.host == "api.2ip.io")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func canonicalizesAddressFromTheAPI() async throws {
        StubURLProtocol.handler = { request in
            let json = #"{"ip":" 045.159.012.007 ","country":"Sweden","code":"SE"}"#
            return (try self.response(request), Data(json.utf8))
        }

        let geo = try await makeClient().currentGeo()
        #expect(geo.ip.description == "45.159.12.7")
    }

    @Test func httpErrorIsReported() async throws {
        StubURLProtocol.handler = { request in
            (try self.response(request, status: 503), Data())
        }

        do {
            _ = try await makeClient().currentGeo()
            Issue.record("expected an error")
        } catch let error as TwoIPError {
            #expect(error == .httpStatus(503))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func noInternetIsReportedAsOffline() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await makeClient().currentGeo()
            Issue.record("expected an error")
        } catch let error as TwoIPError {
            #expect(error == .offline)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func htmlInsteadOfJSONIsInvalid() async throws {
        StubURLProtocol.handler = { request in
            (try self.response(request), Data("<html>loading…</html>".utf8))
        }

        do {
            _ = try await makeClient().currentGeo()
            Issue.record("expected an error")
        } catch let error as TwoIPError {
            #expect(error == .invalidResponse)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func parserRejectsMissingIP() throws {
        let json = #"{"country":"Sweden","code":"SE"}"#
        #expect(throws: TwoIPError.invalidResponse) {
            try TwoIPClient.parseGeo(Data(json.utf8))
        }
    }

    @Test func parserRejectsIPv6() throws {
        let json = #"{"ip":"2001:db8::1","country":"Sweden","code":"SE"}"#
        #expect(throws: TwoIPError.invalidResponse) {
            try TwoIPClient.parseGeo(Data(json.utf8))
        }
    }

    @Test func parserAcceptsMissingCountryFields() throws {
        let geo = try TwoIPClient.parseGeo(Data(#"{"ip":"45.159.12.7"}"#.utf8))
        #expect(geo.ip.description == "45.159.12.7")
        #expect(geo.countryCode == nil)
        #expect(geo.countryName == nil)
        #expect(geo.flag == "🌐")
    }

    @Test func parserNormalizesCountryCodeAndTrimsName() throws {
        let json = #"{"ip":"45.159.12.7","country":" Sweden ","code":"se"}"#
        let geo = try TwoIPClient.parseGeo(Data(json.utf8))
        #expect(geo.countryCode == "SE")
        #expect(geo.countryName == "Sweden")
    }

    @Test func parserRejectsNonJSON() throws {
        #expect(throws: TwoIPError.invalidResponse) {
            try TwoIPClient.parseGeo(Data("<html/>".utf8))
        }
    }
}

extension TwoIPClientTests {
    @Test func fallbackUsesLocalCountry() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { request in
            let status = request.url?.host == "api.2ip.io" ? 503 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ip":"8.8.8.8"}"#.utf8))
        }
        let client = MultiIPClient(session: URLSession(configuration: config), startIndex: 0)
        let geo = try await client.currentGeo()
        #expect(geo.ip.description == "8.8.8.8")
        #expect(geo.countryCode == "US")
        #expect(StubURLProtocol.lastRequest?.url?.host == "api.ipify.org")
    }

    @Test func validatesRangesAndBoundaries() {
        let data = LocalGeoIP.compact("1.0.0.0,1.0.0.255,AU\n1.0.1.0,1.0.1.255,CN\n2001:db8::,2001:db8::ffff,US")
        #expect(data.count == 20)
        #expect(LocalGeoIP.valid(data))
        #expect(!LocalGeoIP.valid(Data(data.dropLast())))
        #expect(!LocalGeoIP.valid(data + data))
    }
}
