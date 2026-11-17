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
            let status = 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ip":"8.8.8.8"}"#.utf8))
        }
        let client = MultiIPClient(session: URLSession(configuration: config), startIndex: 0)
        let geo = try await client.currentGeo()
        #expect(geo.ip.description == "8.8.8.8")
        #expect(geo.countryCode == "US")
        #expect(StubURLProtocol.lastRequest?.url?.host == "api.2ip.io")
    }

    @Test func validatesRangesAndBoundaries() {
        let data = LocalGeoIP.compact("1.0.0.0,1.0.0.255,AU\n1.0.1.0,1.0.1.255,CN\n2001:db8::,2001:db8::ffff,US")
        #expect(data.count == 20)
        #expect(LocalGeoIP.valid(data))
        #expect(!LocalGeoIP.valid(Data(data.dropLast())))
        #expect(!LocalGeoIP.valid(data + data))
    }
}

extension TwoIPClientTests {
    @Test func networkChangeClearsProviderCooldowns() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = MultiIPClient(session: session, startIndex: 0)
        StubURLProtocol.handler = { request in
            (try self.response(request, status: 503), Data())
        }
        do {
            _ = try await client.currentGeo()
            Issue.record("Expected all providers to fail")
        } catch {}

        StubURLProtocol.handler = { request in
            (try self.response(request), Data(#"{"ip":"8.8.8.8","code":"US"}"#.utf8))
        }
        await client.networkDidChange()
        let geo = try await client.currentGeo()
        #expect(geo.ip.description == "8.8.8.8")
    }
    @Test func transitionProbeBypassesDisconnectCooldown() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = MultiIPClient(session: session, startIndex: 0)
        StubURLProtocol.handler = { request in
            (try self.response(request, status: 503), Data())
        }
        do { _ = try await client.currentGeo() } catch {}
        StubURLProtocol.handler = { request in
            (try self.response(request), Data(#"{"ip":"8.8.8.8","code":"US"}"#.utf8))
        }
        let geo = try await client.currentGeoForNetworkTransition()
        #expect(geo.ip.description == "8.8.8.8")
    }

    @Test func unavailableProvidersAreTriedInPriorityOrder() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var hosts: [String] = []
        StubURLProtocol.handler = { request in
            hosts.append(request.url?.host ?? "")
            return (try self.response(request, status: 503), Data())
        }
        let client = MultiIPClient(session: session)
        do {
            _ = try await client.currentGeo()
            Issue.record("Expected an unavailable service")
        } catch {}
        #expect(hosts == ["api.2ip.io", "ipv4.icanhazip.com"])
        hosts.removeAll()
        do {
            _ = try await client.currentGeoForNetworkTransition()
            Issue.record("Expected an unavailable service")
        } catch {}
        #expect(hosts == ["api.2ip.io", "ipv4.icanhazip.com"])
    }

    @Test func rateLimitSurvivesNetworkResetAndTransitionProbes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                    headerFields: ["Retry-After": "120"])!, Data())
        }
        let client = MultiIPClient(session: session)
        do { _ = try await client.currentGeo() } catch {}
        await client.networkDidChange()
        do { _ = try await client.currentGeoForNetworkTransition() } catch {}
        do { _ = try await client.currentGeo() } catch {}
        #expect(requests == 2)
        let date = try #require(await client.nextAllowedRequestDate())
        #expect(date.timeIntervalSinceNow > 115)
    }

    @Test func retryAfterParsesSecondsDateAndDefault() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(MultiIPClient.retryDate("120", now: now) == now.addingTimeInterval(120))
        #expect(MultiIPClient.retryDate(nil, now: now) == now.addingTimeInterval(60))
        #expect(MultiIPClient.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now) == now.addingTimeInterval(120))
    }

}


extension TwoIPClientTests {
    @Test func icanhazipFallbackResolvesCountryLocally() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var hosts: [String] = []
        StubURLProtocol.handler = { request in
            hosts.append(request.url!.host!)
            if request.url?.host == "api.2ip.io" { return (try self.response(request, status: 503), Data()) }
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
            return (try self.response(request), Data("8.8.8.8\n".utf8))
        }
        let client = MultiIPClient(session: URLSession(configuration: configuration))
        let geo = try await client.currentGeoForNetworkTransition()
        #expect(geo.ip.description == "8.8.8.8")
        #expect(geo.countryCode == "US")
        #expect(hosts == ["api.2ip.io", "ipv4.icanhazip.com"])
    }

    @Test func preferredProviderIsAlwaysFirstAndCanBeChanged() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var hosts: [String] = []
        StubURLProtocol.handler = { request in
            hosts.append(request.url!.host!)
            let body = request.url?.host == "api.2ip.io"
                ? #"{"ip":"8.8.8.8","code":"US"}"# : "1.1.1.1\n"
            return (try self.response(request), Data(body.utf8))
        }
        let client = MultiIPClient(session: URLSession(configuration: configuration), preferredProvider: .icanhazip)
        #expect(try await client.currentGeo().ip.description == "1.1.1.1")
        #expect(try await client.currentGeo().ip.description == "1.1.1.1")
        await client.setPreferredProvider(.twoIP)
        #expect(try await client.currentGeo().ip.description == "8.8.8.8")
        #expect(hosts == ["ipv4.icanhazip.com", "ipv4.icanhazip.com", "api.2ip.io"])
    }

    @Test func rateLimitedPreferredProviderDoesNotBlockFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var hosts: [String] = []
        StubURLProtocol.handler = { request in
            hosts.append(request.url!.host!)
            if request.url?.host == "api.2ip.io" {
                return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                        headerFields: ["Retry-After": "120"])!, Data())
            }
            return (try self.response(request), Data("8.8.8.8\n".utf8))
        }
        let client = MultiIPClient(session: URLSession(configuration: configuration))
        #expect(try await client.currentGeo().ip.description == "8.8.8.8")
        await client.networkDidChange()
        #expect(try await client.currentGeoForNetworkTransition().ip.description == "8.8.8.8")
        #expect(hosts == ["api.2ip.io", "ipv4.icanhazip.com", "ipv4.icanhazip.com"])
        #expect(await client.nextAllowedRequestDate() == nil)
    }

    @Test func invalidPlainTextFallsBackToTwoIP() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        for body in ["2001:db8::1", "127.0.0.1", "<html>error</html>", "8.8.8.8\n1.1.1.1"] {
            var hosts: [String] = []
            StubURLProtocol.handler = { request in
                hosts.append(request.url!.host!)
                let data = request.url?.host == "api.2ip.io"
                    ? Data(#"{"ip":"8.8.8.8","code":"US"}"#.utf8) : Data(body.utf8)
                return (try self.response(request), data)
            }
            let client = MultiIPClient(session: URLSession(configuration: configuration), preferredProvider: .icanhazip)
            #expect(try await client.currentGeo().ip.description == "8.8.8.8")
            #expect(hosts == ["ipv4.icanhazip.com", "api.2ip.io"])
        }
    }
}
