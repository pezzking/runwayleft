import XCTest
@testable import RunwayLeft

final class ModelUsageAggregatorTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!

    private func sample() -> (ClaudeUsageData, CodexUsageData) {
        var claude = ClaudeUsageData()
        claude.dailyModelTokens = [
            ClaudeDailyModelTokens(date: "2026-09-03", tokensByModel: ["fable": 100]),
            ClaudeDailyModelTokens(date: "2026-09-01", tokensByModel: ["fable": 50, "sonnet": 5]),
            ClaudeDailyModelTokens(date: "2026-08-28", tokensByModel: ["fable": 20]),   // 7-day boundary, inclusive
            ClaudeDailyModelTokens(date: "2026-08-27", tokensByModel: ["fable": 1_000]), // just outside 7 days
            ClaudeDailyModelTokens(date: "2026-08-01", tokensByModel: ["opus": 500]),
            ClaudeDailyModelTokens(date: "2025-01-01", tokensByModel: ["haiku": 9_000])
        ]
        claude.modelUsage = [
            ClaudeModelDetail(modelName: "fable", inputTokens: 70_000, outputTokens: 0, cacheReadInputTokens: 999_999, cacheCreationInputTokens: 0),
            ClaudeModelDetail(modelName: "opus", inputTokens: 500, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
        ]

        var codex = CodexUsageData()
        codex.dailyModelTokens = [
            CodexDailyModelTokens(date: "2026-09-03", modelName: "gpt-5.6", sessionCount: 1, tokens: 300),
            CodexDailyModelTokens(date: "2026-08-20", modelName: "gpt-5.6", sessionCount: 2, tokens: 100),
            CodexDailyModelTokens(date: "2025-06-01", modelName: "o4-mini", sessionCount: 1, tokens: 10)
        ]
        codex.modelBreakdown = [
            CodexModelUsage(modelName: "gpt-5.6", sessionCount: 3, totalTokens: 400),
            CodexModelUsage(modelName: "o4-mini", sessionCount: 1, totalTokens: 10)
        ]
        return (claude, codex)
    }

    private func tokens(_ entries: [ModelUsageEntry], _ agent: UsageAgent, _ model: String) -> Int64? {
        entries.first { $0.agent == agent && $0.modelName == model }?.tokens
    }

    func testDateBoundsAreInclusiveAndCountToday() throws {
        let week = try XCTUnwrap(ModelUsageAggregator.dateBounds(for: .week, now: now, calendar: utcCalendar))
        XCTAssertEqual(week.start, "2026-08-28")
        XCTAssertEqual(week.end, "2026-09-03")

        let day = try XCTUnwrap(ModelUsageAggregator.dateBounds(for: .day, now: now, calendar: utcCalendar))
        XCTAssertEqual(day.start, "2026-09-03")
        XCTAssertEqual(day.end, "2026-09-03")

        XCTAssertNil(ModelUsageAggregator.dateBounds(for: .all, now: now, calendar: utcCalendar))
    }

    func testTodayOnlyCountsTodaysBuckets() {
        let (claude, codex) = sample()
        let entries = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .day, now: now, calendar: utcCalendar)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(tokens(entries, .codex, "gpt-5.6"), 300)
        XCTAssertEqual(tokens(entries, .claude, "fable"), 100)
        XCTAssertEqual(entries.first?.modelName, "gpt-5.6", "sorted by tokens descending")
    }

    func testWeekIncludesBoundaryDayAndExcludesTheDayBefore() {
        let (claude, codex) = sample()
        let entries = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .week, now: now, calendar: utcCalendar)

        XCTAssertEqual(tokens(entries, .claude, "fable"), 170) // 100 + 50 + 20, not the 1,000 from Aug 27
        XCTAssertEqual(tokens(entries, .claude, "sonnet"), 5)
        XCTAssertEqual(tokens(entries, .codex, "gpt-5.6"), 300)
        XCTAssertNil(tokens(entries, .claude, "opus"))
    }

    func testMonthAndSixMonthsWidenTheWindow() {
        let (claude, codex) = sample()

        let month = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .month, now: now, calendar: utcCalendar)
        XCTAssertEqual(tokens(month, .claude, "fable"), 1_170)
        XCTAssertEqual(tokens(month, .codex, "gpt-5.6"), 400)
        XCTAssertNil(tokens(month, .claude, "opus"), "Aug 1 is outside 30 days")

        let sixMonths = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .sixMonths, now: now, calendar: utcCalendar)
        XCTAssertEqual(tokens(sixMonths, .claude, "opus"), 500)
        XCTAssertNil(tokens(sixMonths, .codex, "o4-mini"), "June 2025 is outside 6 months")
    }

    func testYearExcludesOlderDataAndAllTimeUsesAllTimeTables() {
        let (claude, codex) = sample()

        let year = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .year, now: now, calendar: utcCalendar)
        XCTAssertNil(tokens(year, .claude, "haiku"))
        XCTAssertNil(tokens(year, .codex, "o4-mini"), "June 1 2025 is outside 365 days from Sep 3 2026")

        let all = ModelUsageAggregator.entries(claude: claude, codex: codex, range: .all, now: now, calendar: utcCalendar)
        XCTAssertEqual(tokens(all, .claude, "fable"), 70_000, "all-time uses modelUsage, which excludes cache reads")
        XCTAssertEqual(tokens(all, .claude, "opus"), 500)
        XCTAssertNil(tokens(all, .claude, "haiku"), "not present in the all-time table")
        XCTAssertEqual(tokens(all, .codex, "gpt-5.6"), 400)
        XCTAssertEqual(tokens(all, .codex, "o4-mini"), 10)
    }

    func testZeroTokenEntriesAreDropped() {
        var claude = ClaudeUsageData()
        claude.dailyModelTokens = [ClaudeDailyModelTokens(date: "2026-09-03", tokensByModel: ["empty": 0])]
        let entries = ModelUsageAggregator.entries(claude: claude, codex: CodexUsageData(), range: .day, now: now, calendar: utcCalendar)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSpanLabels() {
        XCTAssertEqual(ModelUsageAggregator.spanLabel(for: .all, now: now, calendar: utcCalendar), "All time")
        XCTAssertEqual(ModelUsageAggregator.spanLabel(for: .day, now: now, calendar: utcCalendar), "Sep 3")
        XCTAssertEqual(ModelUsageAggregator.spanLabel(for: .week, now: now, calendar: utcCalendar), "Aug 28 – Sep 3")
    }
}
