import XCTest
@testable import RunwayLeft

/// Exercises `LiteLLMDataReader`'s request flow against a stubbed URL protocol:
/// auth header, `/key/info` fallback, pagination, and error mapping. No sockets.
final class LiteLLMReaderNetworkTests: XCTestCase {
    final class StubURLProtocol: URLProtocol {
        typealias Handler = (URLRequest) -> (status: Int, body: Data)?
        static var handler: Handler = { _ in nil }
        static var requests: [URLRequest] = []
        static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            let response = Self.handler(request)
            Self.lock.unlock()

            guard let response = response else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var reader: LiteLLMDataReader!
    private let config = LiteLLMDataReader.Config(endpoint: "http://proxy.test:4000", apiKey: "sk-test-123")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { _ in nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        reader = LiteLLMDataReader(session: URLSession(configuration: configuration))
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func path(_ request: URLRequest) -> String { request.url?.path ?? "" }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private let keyInfo = #"{"key":"sk","info":{"key_alias":"dev","spend":25,"max_budget":50,"budget_duration":"monthly"}}"#

    private func dailyPage(_ page: Int, total: Int, date: String, tokens: Int) -> String {
        """
        {"results":[{"date":"\(date)","metrics":{"spend":1.5,"prompt_tokens":10,"completion_tokens":20,"total_tokens":\(tokens),"api_requests":3},
                     "breakdown":{"models":{"gpt-4o-mini":{"metrics":{"spend":1.5,"total_tokens":\(tokens),"api_requests":3}}}}}],
         "metadata":{"page":\(page),"total_pages":\(total),"has_more":\(page < total)}}
        """
    }

    func testFetchSendsBearerTokenFollowsPagesAndBuildsData() {
        StubURLProtocol.handler = { [self] request in
            switch path(request) {
            case "/key/info": return (200, json(keyInfo))
            case "/user/daily/activity":
                let page = Int(query(request, "page") ?? "1") ?? 1
                return (200, json(dailyPage(page, total: 2, date: page == 1 ? "2026-09-03" : "2026-09-04", tokens: page * 100)))
            default: return (404, json("{}"))
            }
        }

        let done = expectation(description: "fetch")
        var result: LiteLLMUsageData?
        reader.fetch(config: config, days: 14) { data in
            result = data
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        let data = try! XCTUnwrap(result)
        XCTAssertEqual(data.connection, .connected)
        XCTAssertEqual(data.keyAlias, "dev")
        XCTAssertEqual(data.maxBudget, 50)
        XCTAssertEqual(data.budgetUsedPct ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(data.daily.map { $0.date }, ["2026-09-03", "2026-09-04"], "both pages merged, oldest first")
        XCTAssertEqual(data.dailyModelTokens.count, 2)
        XCTAssertEqual(data.endpointHost, "proxy.test")
        XCTAssertEqual(data.windowDays, 14)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123" })
        let pages = requests.filter { path($0) == "/user/daily/activity" }
        XCTAssertEqual(pages.compactMap { query($0, "page") }, ["1", "2"])
        XCTAssertEqual(query(pages[0], "page_size"), String(LiteLLMDataReader.pageSize))
        XCTAssertNotNil(query(pages[0], "start_date"))
        XCTAssertNotNil(query(pages[0], "end_date"))
    }

    func testKeyInfoRetriesWithExplicitKeyWhenRequired() {
        StubURLProtocol.handler = { [self] request in
            switch path(request) {
            case "/key/info":
                return query(request, "key") == nil ? (400, json(#"{"error":"key required"}"#)) : (200, json(keyInfo))
            case "/user/daily/activity":
                return (200, json(dailyPage(1, total: 1, date: "2026-09-04", tokens: 5)))
            default: return (404, json("{}"))
            }
        }

        let done = expectation(description: "fetch")
        var result: LiteLLMUsageData?
        reader.fetch(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.maxBudget, 50)
        XCTAssertEqual(StubURLProtocol.requests.filter { path($0) == "/key/info" }.count, 2)
    }

    func testUnauthorizedIsReported() {
        StubURLProtocol.handler = { [self] _ in (401, json(#"{"error":{"message":"Authentication Error"}}"#)) }

        let done = expectation(description: "fetch")
        var result: LiteLLMUsageData?
        reader.fetch(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.connection, .unauthorized)
        XCTAssertNil(result?.maxBudget)
        XCTAssertTrue(result?.daily.isEmpty ?? false)
    }

    func testMissingDatabaseIsReportedAsNoSpendTracking() {
        StubURLProtocol.handler = { [self] request in
            path(request) == "/key/info"
                ? (500, json(#"{"error":{"message":"Database not connected. Connect a database to your proxy"}}"#))
                : (500, json(#"{"detail":"No database connected"}"#))
        }

        let done = expectation(description: "fetch")
        var result: LiteLLMUsageData?
        reader.fetch(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.connection, .noSpendTracking)
    }

    func testTransportFailureIsUnreachable() {
        StubURLProtocol.handler = { _ in nil }

        let done = expectation(description: "fetch")
        var result: LiteLLMUsageData?
        reader.fetch(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        if case .unreachable = result?.connection {} else {
            XCTFail("expected unreachable, got \(String(describing: result?.connection))")
        }
    }

    func testConnectionTestReportsThreeStages() {
        StubURLProtocol.handler = { [self] request in
            switch path(request) {
            case "/health/liveliness": return (200, json(#""I'm alive!""#))
            case "/key/info": return (200, json(keyInfo))
            case "/user/daily/activity": return (200, json(dailyPage(1, total: 1, date: DayFormat.today, tokens: 42)))
            default: return (404, json("{}"))
            }
        }

        let done = expectation(description: "test")
        var result: LiteLLMDataReader.ConnectionTest?
        reader.testConnection(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        let test = try! XCTUnwrap(result)
        XCTAssertEqual(test.state, .connected)
        if case .passed(let message) = test.reachable { XCTAssertTrue(message.contains("proxy.test")) } else { XCTFail() }
        if case .passed(let message) = test.authenticated { XCTAssertTrue(message.contains("dev")); XCTAssertTrue(message.contains("$50")) } else { XCTFail() }
        if case .passed(let message) = test.spendTracking { XCTAssertTrue(message.contains("42")) } else { XCTFail() }
    }

    func testConnectionTestStopsAtRejectedKey() {
        StubURLProtocol.handler = { [self] request in
            path(request) == "/health/liveliness" ? (200, json(#""I'm alive!""#)) : (403, json("{}"))
        }

        let done = expectation(description: "test")
        var result: LiteLLMDataReader.ConnectionTest?
        reader.testConnection(config: config) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.state, .unauthorized)
        XCTAssertNil(result?.spendTracking, "does not probe spend tracking after the key is rejected")
    }
}
