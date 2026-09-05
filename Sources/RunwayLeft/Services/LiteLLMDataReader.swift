import Foundation

/// Talks to a LiteLLM proxy with the user's virtual key.
///
/// Two endpoints: `/key/info` for the key's spend and budget, and
/// `/user/daily/activity` for per-day, per-model spend/tokens/requests. Both
/// need the proxy to have a database; without one they fail and the reader
/// reports `.noSpendTracking`.
class LiteLLMDataReader {
    struct Config: Equatable {
        let endpoint: URL
        let apiKey: String

        /// Accepts "localhost:4000", "http://host", or a full URL; nil when empty.
        init?(endpoint raw: String, apiKey: String) {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !key.isEmpty else { return nil }
            if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
                text = "http://" + text
            }
            while text.hasSuffix("/") { text.removeLast() }
            guard let url = URL(string: text), url.host != nil else { return nil }
            self.endpoint = url
            self.apiKey = key
        }
    }

    struct KeyInfo: Equatable {
        var alias: String = ""
        var spend: Double? = nil
        var maxBudget: Double? = nil
        var budgetResetAt: Date? = nil
        var budgetDuration: String? = nil
        var tpmLimit: Int? = nil
        var rpmLimit: Int? = nil
    }

    struct DailyActivityPage: Equatable {
        var daily: [LiteLLMDailyUsage] = []
        var models: [LiteLLMDailyModelUsage] = []
        var page: Int = 1
        var totalPages: Int = 1
        var hasMore: Bool = false
    }

    /// Outcome of the Settings "Test connection" button, one line per stage.
    struct ConnectionTest: Equatable {
        enum Stage: Equatable {
            case passed(String)
            case failed(String)
        }
        var reachable: Stage
        var authenticated: Stage?
        var spendTracking: Stage?
        var state: LiteLLMConnectionState
    }

    enum ParseError: Error {
        case malformed
    }

    static let maxPages = 12
    static let pageSize = 100

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 40
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Parsing (pure)

    static func parseKeyInfo(_ data: Data) throws -> KeyInfo {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.malformed }
        // /key/info wraps the row in "info"; tolerate a bare row too.
        let info = (root["info"] as? [String: Any]) ?? root
        var result = KeyInfo()
        result.alias = (info["key_alias"] as? String) ?? (info["key_name"] as? String) ?? ""
        result.spend = (info["spend"] as? NSNumber)?.doubleValue
        result.maxBudget = (info["max_budget"] as? NSNumber)?.doubleValue
        result.budgetDuration = info["budget_duration"] as? String
        result.budgetResetAt = VendorStatusService.parseDate(info["budget_reset_at"] as? String)
        result.tpmLimit = (info["tpm_limit"] as? NSNumber)?.intValue
        result.rpmLimit = (info["rpm_limit"] as? NSNumber)?.intValue
        return result
    }

    static func parseDailyActivity(_ data: Data) throws -> DailyActivityPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { throw ParseError.malformed }

        var page = DailyActivityPage()
        for row in results {
            guard let date = row["date"] as? String else { continue }
            let metrics = (row["metrics"] as? [String: Any]) ?? [:]
            page.daily.append(LiteLLMDailyUsage(
                date: date,
                spend: number(metrics["spend"]),
                promptTokens: Int64(number(metrics["prompt_tokens"])),
                completionTokens: Int64(number(metrics["completion_tokens"])),
                totalTokens: Int64(number(metrics["total_tokens"])),
                requests: Int(number(metrics["api_requests"]))
            ))

            let breakdown = (row["breakdown"] as? [String: Any]) ?? [:]
            let models = (breakdown["models"] as? [String: Any]) ?? [:]
            for (model, value) in models {
                guard let entry = value as? [String: Any] else { continue }
                // Newer proxies nest the numbers under "metrics"; older ones inline them.
                let m = (entry["metrics"] as? [String: Any]) ?? entry
                page.models.append(LiteLLMDailyModelUsage(
                    date: date,
                    modelName: model,
                    spend: number(m["spend"]),
                    tokens: Int64(number(m["total_tokens"])),
                    requests: Int(number(m["api_requests"]))
                ))
            }
        }

        page.daily.sort { $0.date < $1.date }
        page.models.sort { ($0.date, $0.modelName) < ($1.date, $1.modelName) }

        let metadata = (root["metadata"] as? [String: Any]) ?? [:]
        page.page = Int(number(metadata["page"], default: 1))
        page.totalPages = Int(number(metadata["total_pages"], default: 1))
        page.hasMore = (metadata["has_more"] as? Bool) ?? (page.page < page.totalPages)
        return page
    }

    /// Maps an HTTP failure to what the user should be told.
    static func classifyFailure(status: Int, body: Data?) -> LiteLLMConnectionState {
        let text = body.flatMap { String(data: $0, encoding: .utf8) }?.lowercased() ?? ""
        if status == 401 || status == 403 {
            return .unauthorized
        }
        if text.contains("database") || text.contains("db not connected") || text.contains("prisma") || text.contains("no db") {
            return .noSpendTracking
        }
        let snippet = text.prefix(120).replacingOccurrences(of: "\n", with: " ")
        return .error(snippet.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(snippet)")
    }

    private static func number(_ value: Any?, default fallback: Double = 0) -> Double {
        (value as? NSNumber)?.doubleValue ?? fallback
    }

    // MARK: - Requests

    private func request(_ config: Config, path: String, query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(url: config.endpoint.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private enum Outcome {
        case success(Data)
        case http(Int, Data?)
        case transport(String)
    }

    private func perform(_ request: URLRequest, completion: @escaping (Outcome) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.transport(error.localizedDescription))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status), let data = data {
                completion(.success(data))
            } else {
                completion(.http(status, data))
            }
        }.resume()
    }

    /// Full refresh: key info (budget) plus the daily window, paged.
    func fetch(config: Config, days: Int = 365, now: Date = Date(), calendar: Calendar = .current, completion: @escaping (LiteLLMUsageData) -> Void) {
        var data = LiteLLMUsageData()
        data.isConfigured = true
        data.endpointHost = config.endpoint.host ?? config.endpoint.absoluteString
        data.windowDays = days

        let end = DayFormat.string(from: now, calendar: calendar)
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        let start = DayFormat.string(from: startDate, calendar: calendar)

        fetchKeyInfo(config) { [weak self] keyInfo, keyFailure in
            guard let self = self else { return }
            if let info = keyInfo {
                data.keyAlias = info.alias
                data.spend = info.spend
                data.maxBudget = info.maxBudget
                data.budgetResetAt = info.budgetResetAt
                data.budgetDuration = info.budgetDuration
                data.tpmLimit = info.tpmLimit
                data.rpmLimit = info.rpmLimit
            }

            self.fetchDailyPages(config, start: start, end: end, page: 1, accumulated: DailyActivityPage()) { pageResult, failure in
                data.fetchedAt = Date()
                if let page = pageResult {
                    data.daily = page.daily
                    data.dailyModelTokens = page.models
                    data.connection = .connected
                } else if let failure = failure {
                    data.connection = failure
                } else if let keyFailure = keyFailure {
                    data.connection = keyFailure
                } else {
                    data.connection = .error("No data returned")
                }
                completion(data)
            }
        }
    }

    private func fetchKeyInfo(_ config: Config, completion: @escaping (KeyInfo?, LiteLLMConnectionState?) -> Void) {
        perform(request(config, path: "key/info")) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .success(let data):
                completion(try? Self.parseKeyInfo(data), nil)
            case .http(let status, let body):
                // Some versions require the key to be named explicitly.
                if status == 400 || status == 422 {
                    self.perform(self.request(config, path: "key/info", query: ["key": config.apiKey])) { retry in
                        switch retry {
                        case .success(let data): completion(try? Self.parseKeyInfo(data), nil)
                        case .http(let s, let b): completion(nil, Self.classifyFailure(status: s, body: b))
                        case .transport(let message): completion(nil, .unreachable(message))
                        }
                    }
                } else {
                    completion(nil, Self.classifyFailure(status: status, body: body))
                }
            case .transport(let message):
                completion(nil, .unreachable(message))
            }
        }
    }

    private func fetchDailyPages(
        _ config: Config, start: String, end: String, page: Int, accumulated: DailyActivityPage,
        completion: @escaping (DailyActivityPage?, LiteLLMConnectionState?) -> Void
    ) {
        let query = ["start_date": start, "end_date": end, "page": String(page), "page_size": String(Self.pageSize)]
        perform(request(config, path: "user/daily/activity", query: query)) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .success(let data):
                guard let parsed = try? Self.parseDailyActivity(data) else {
                    completion(nil, .error("Unexpected response from /user/daily/activity"))
                    return
                }
                var merged = accumulated
                merged.daily.append(contentsOf: parsed.daily)
                merged.models.append(contentsOf: parsed.models)
                merged.page = parsed.page
                merged.totalPages = parsed.totalPages
                merged.hasMore = parsed.hasMore
                if parsed.hasMore && page < Self.maxPages && !parsed.daily.isEmpty {
                    self.fetchDailyPages(config, start: start, end: end, page: page + 1, accumulated: merged, completion: completion)
                } else {
                    merged.daily.sort { $0.date < $1.date }
                    merged.models.sort { ($0.date, $0.modelName) < ($1.date, $1.modelName) }
                    completion(merged, nil)
                }
            case .http(let status, let body):
                completion(nil, Self.classifyFailure(status: status, body: body))
            case .transport(let message):
                completion(nil, .unreachable(message))
            }
        }
    }

    /// Three-stage probe for Settings: reachable, authenticated, spend tracking.
    func testConnection(config: Config, completion: @escaping (ConnectionTest) -> Void) {
        var liveness = URLRequest(url: config.endpoint.appendingPathComponent("health/liveliness"))
        liveness.httpMethod = "GET"

        perform(liveness) { [weak self] outcome in
            guard let self = self else { return }
            let host = config.endpoint.absoluteString
            switch outcome {
            case .transport(let message):
                completion(ConnectionTest(reachable: .failed("Cannot reach \(host): \(message)"), state: .unreachable(message)))
                return
            case .http(let status, _):
                // Liveliness is unauthenticated; anything but a transport error means the host answers.
                _ = status
            case .success:
                break
            }

            var test = ConnectionTest(reachable: .passed("Proxy answers at \(host)"), state: .unknown)

            self.fetchKeyInfo(config) { info, failure in
                if let info = info {
                    let budget = info.maxBudget.map { LiteLLMUsageData.formatSpend($0) } ?? "no budget set"
                    let alias = info.alias.isEmpty ? "key accepted" : "key “\(info.alias)”"
                    test.authenticated = .passed("\(alias), spend \(LiteLLMUsageData.formatSpend(info.spend ?? 0)), budget \(budget)")
                } else if let failure = failure {
                    test.authenticated = .failed(failure.detail ?? failure.label)
                    if failure == .unauthorized || failure == .noSpendTracking {
                        test.state = failure
                        completion(test)
                        return
                    }
                }

                let end = DayFormat.today
                self.fetchDailyPages(config, start: end, end: end, page: 1, accumulated: DailyActivityPage()) { page, failure in
                    if let page = page {
                        let today = page.daily.first
                        let tokens = UsageManager.formatTokens(today?.totalTokens ?? 0)
                        test.spendTracking = .passed("Daily activity available (today: \(tokens) tokens, \(today?.requests ?? 0) requests)")
                        test.state = .connected
                    } else if let failure = failure {
                        test.spendTracking = .failed(failure.detail ?? failure.label)
                        test.state = failure
                    }
                    completion(test)
                }
            }
        }
    }
}
