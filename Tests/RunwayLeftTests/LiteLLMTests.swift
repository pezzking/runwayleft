import XCTest
@testable import RunwayLeft

final class LiteLLMTests: XCTestCase {
    // Shape from docs.litellm.ai/docs/proxy/cost_tracking, with the newer
    // "metrics"/"metadata" nesting on one model and the older inline form on another.
    private let dailyActivity = """
    {
      "results": [
        {
          "date": "2026-09-03",
          "metrics": {"spend": 0.0177072, "prompt_tokens": 111, "completion_tokens": 1711, "total_tokens": 1822, "api_requests": 11},
          "breakdown": {
            "models": {
              "gpt-4o-mini": {"metrics": {"spend": 1.095e-05, "prompt_tokens": 37, "completion_tokens": 9, "total_tokens": 46, "api_requests": 1}, "metadata": {}},
              "claude-sonnet": {"spend": 0.0177, "prompt_tokens": 74, "completion_tokens": 1702, "total_tokens": 1776, "api_requests": 10}
            },
            "providers": {"openai": {"metrics": {"spend": 1.095e-05}}},
            "api_keys": {"3126b6eaf1": {"metrics": {"spend": 0.0177072}}}
          }
        },
        {
          "date": "2026-09-04",
          "metrics": {"spend": 0.5, "prompt_tokens": 1000.0, "completion_tokens": 2000.0, "total_tokens": 3000.0, "api_requests": 3},
          "breakdown": {"models": {"gpt-4o-mini": {"metrics": {"spend": 0.5, "total_tokens": 3000, "api_requests": 3}}}}
        }
      ],
      "metadata": {"total_spend": 0.5177072, "total_prompt_tokens": 1111, "total_completion_tokens": 3711, "total_api_requests": 14, "page": 1, "total_pages": 1, "has_more": false}
    }
    """

    private let keyInfo = """
    {
      "key": "sk-tXL0wt5-lOOVK9sfY2UacA",
      "info": {
        "token": "hashed",
        "key_alias": "developer-1",
        "spend": 12.3456,
        "max_budget": 100.0,
        "budget_duration": "monthly",
        "budget_reset_at": "2026-10-01T00:00:00.000Z",
        "tpm_limit": 200000,
        "rpm_limit": 60,
        "models": ["gpt-4o-mini"],
        "expires": null,
        "metadata": {}
      }
    }
    """

    func testParsesDailyActivityWithBothModelBreakdownShapes() throws {
        let page = try LiteLLMDataReader.parseDailyActivity(Data(dailyActivity.utf8))

        XCTAssertEqual(page.daily.map { $0.date }, ["2026-09-03", "2026-09-04"], "oldest first")
        XCTAssertEqual(page.daily[0].totalTokens, 1822)
        XCTAssertEqual(page.daily[0].requests, 11)
        XCTAssertEqual(page.daily[0].spend, 0.0177072, accuracy: 1e-9)
        XCTAssertEqual(page.daily[1].totalTokens, 3000, "float token counts are accepted")

        let models = page.models
        XCTAssertEqual(models.count, 3)
        XCTAssertEqual(models.first { $0.date == "2026-09-03" && $0.modelName == "gpt-4o-mini" }?.tokens, 46)
        XCTAssertEqual(models.first { $0.date == "2026-09-03" && $0.modelName == "claude-sonnet" }?.tokens, 1776, "older inline shape")
        XCTAssertEqual(models.first { $0.date == "2026-09-04" }?.requests, 3)

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 1)
        XCTAssertFalse(page.hasMore)
    }

    func testPaginationMetadataIsRead() throws {
        let json = """
        {"results": [{"date": "2026-01-01", "metrics": {"total_tokens": 5}}], "metadata": {"page": 2, "total_pages": 4, "has_more": true}}
        """
        let page = try LiteLLMDataReader.parseDailyActivity(Data(json.utf8))
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 4)
        XCTAssertTrue(page.hasMore)
    }

    func testParsesKeyInfoBudgetFields() throws {
        let info = try LiteLLMDataReader.parseKeyInfo(Data(keyInfo.utf8))
        XCTAssertEqual(info.alias, "developer-1")
        XCTAssertEqual(info.spend ?? 0, 12.3456, accuracy: 1e-6)
        XCTAssertEqual(info.maxBudget, 100)
        XCTAssertEqual(info.budgetDuration, "monthly")
        XCTAssertNotNil(info.budgetResetAt)
        XCTAssertEqual(info.tpmLimit, 200_000)
        XCTAssertEqual(info.rpmLimit, 60)
    }

    func testKeyWithoutBudgetHasNoPercentage() throws {
        let json = #"{"key": "sk-x", "info": {"spend": 1.5, "max_budget": null}}"#
        let info = try LiteLLMDataReader.parseKeyInfo(Data(json.utf8))
        XCTAssertNil(info.maxBudget)

        var data = LiteLLMUsageData()
        data.spend = info.spend
        data.maxBudget = info.maxBudget
        XCTAssertFalse(data.hasBudget)
        XCTAssertNil(data.budgetUsedPct)

        data.maxBudget = 10
        XCTAssertEqual(data.budgetUsedPct ?? 0, 15, accuracy: 1e-9)
    }

    func testMalformedPayloadsThrow() {
        XCTAssertThrowsError(try LiteLLMDataReader.parseDailyActivity(Data("nope".utf8)))
        XCTAssertThrowsError(try LiteLLMDataReader.parseDailyActivity(Data(#"{"data": []}"#.utf8)))
        XCTAssertThrowsError(try LiteLLMDataReader.parseKeyInfo(Data("[]".utf8)))
    }

    func testFailuresAreClassified() {
        XCTAssertEqual(LiteLLMDataReader.classifyFailure(status: 401, body: nil), .unauthorized)
        XCTAssertEqual(LiteLLMDataReader.classifyFailure(status: 403, body: Data("forbidden".utf8)), .unauthorized)
        XCTAssertEqual(
            LiteLLMDataReader.classifyFailure(status: 500, body: Data(#"{"error": {"message": "Database not connected. Connect a database to your proxy"}}"#.utf8)),
            .noSpendTracking
        )
        if case .error(let message) = LiteLLMDataReader.classifyFailure(status: 502, body: Data("bad gateway".utf8)) {
            XCTAssertTrue(message.contains("502"))
        } else {
            XCTFail("expected a generic error")
        }
    }

    func testConfigNormalizesEndpoints() {
        XCTAssertEqual(LiteLLMDataReader.Config(endpoint: "localhost:4000", apiKey: "sk-1")?.endpoint.absoluteString, "http://localhost:4000")
        XCTAssertEqual(LiteLLMDataReader.Config(endpoint: " https://llm.example.com/ ", apiKey: "sk-1")?.endpoint.absoluteString, "https://llm.example.com")
        XCTAssertNil(LiteLLMDataReader.Config(endpoint: "", apiKey: "sk-1"))
        XCTAssertNil(LiteLLMDataReader.Config(endpoint: "localhost:4000", apiKey: "  "))
    }

    func testConnectionStateLevels() {
        XCTAssertEqual(LiteLLMConnectionState.connected.level, .operational)
        XCTAssertTrue(LiteLLMConnectionState.unreachable("timeout").isProblem)
        XCTAssertTrue(LiteLLMConnectionState.unauthorized.isProblem)
        XCTAssertFalse(LiteLLMConnectionState.unknown.isProblem)
    }

    // MARK: - Integration with the shared aggregations

    private func sampleData() -> LiteLLMUsageData {
        var data = LiteLLMUsageData()
        data.isConfigured = true
        data.connection = .connected
        data.fetchedAt = Date()
        data.spend = 40
        data.maxBudget = 100
        data.daily = [
            LiteLLMDailyUsage(date: "2026-09-03", spend: 0.5, promptTokens: 100, completionTokens: 200, totalTokens: 300, requests: 2),
            LiteLLMDailyUsage(date: "2026-09-04", spend: 1.0, promptTokens: 400, completionTokens: 300, totalTokens: 700, requests: 5)
        ]
        data.dailyModelTokens = [
            LiteLLMDailyModelUsage(date: "2026-09-03", modelName: "gpt-4o-mini", spend: 0.5, tokens: 300, requests: 2),
            LiteLLMDailyModelUsage(date: "2026-09-04", modelName: "gpt-4o-mini", spend: 0.6, tokens: 400, requests: 3),
            LiteLLMDailyModelUsage(date: "2026-09-04", modelName: "claude-sonnet", spend: 0.4, tokens: 300, requests: 2)
        ]
        return data
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCombinedPointsIncludeLiteLLMSeries() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z"))
        let points = UsageManager.computeCombinedPoints(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: sampleData(), now: now, calendar: utcCalendar)

        XCTAssertEqual(points.last?.liteLLMTokens, 700)
        XCTAssertEqual(points.last?.totalTokens, 700)
        XCTAssertEqual(points[points.count - 2].liteLLMTokens, 300)
        XCTAssertEqual(points.first?.liteLLMTokens, 0)
    }

    func testModelEntriesIncludeLiteLLMModels() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z"))
        let day = ModelUsageAggregator.entries(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: sampleData(), range: .day, now: now, calendar: utcCalendar)
        XCTAssertEqual(day.first { $0.agent == .litellm && $0.modelName == "gpt-4o-mini" }?.tokens, 400)
        XCTAssertEqual(day.first { $0.agent == .litellm && $0.modelName == "claude-sonnet" }?.tokens, 300)

        let all = ModelUsageAggregator.entries(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: sampleData(), range: .all, now: now, calendar: utcCalendar)
        XCTAssertEqual(all.first { $0.agent == .litellm && $0.modelName == "gpt-4o-mini" }?.tokens, 700, "all time is the fetched window")
    }

    func testMenuBarShowsBudgetOnlyWhenPresentAndFlagsProblems() {
        var options = MenuBarOptions()
        options.style = .quotasOnly

        let withBudget = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: sampleData(), options: options)
        XCTAssertEqual(withBudget.map { $0.icon }, [.litellm])
        XCTAssertEqual(withBudget[0].text, "40%")
        XCTAssertNil(withBudget[0].alert)

        var noBudget = sampleData()
        noBudget.maxBudget = nil
        let without = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: noBudget, options: options)
        XCTAssertEqual(without.map { $0.icon }, [.app], "falls back to the app glyph with nothing to show")

        let unreachable = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: CodexUsageData(), litellm: sampleData(), liteLLMStatus: .majorOutage, options: options)
        XCTAssertEqual(unreachable[0].alert, .majorOutage)

        // Default (not configured) data adds nothing, so existing behavior is untouched.
        let none = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: CodexUsageData(), options: MenuBarOptions())
        XCTAssertFalse(none.contains { $0.icon == .litellm })
    }

    func testCredentialStoreWritesOwnerOnlyFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runwayleft-cred-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CredentialStore(directory: dir)

        XCTAssertNil(store.load("litellm.key"))
        store.save("  sk-secret-123 \n", as: "litellm.key")
        XCTAssertEqual(store.load("litellm.key"), "sk-secret-123")

        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("litellm.key").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        store.save("", as: "litellm.key")
        XCTAssertNil(store.load("litellm.key"), "saving an empty value deletes the file")
    }

    func testSpendFormatting() {
        XCTAssertEqual(LiteLLMUsageData.formatSpend(0), "$0")
        XCTAssertEqual(LiteLLMUsageData.formatSpend(0.0177), "$0.018")
        XCTAssertEqual(LiteLLMUsageData.formatSpend(12.3456), "$12.35")
        XCTAssertEqual(LiteLLMUsageData.formatSpend(1234), "$1234")
    }
}
