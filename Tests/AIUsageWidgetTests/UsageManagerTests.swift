import XCTest
@testable import AIUsageWidget

final class UsageManagerTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCombinedPointsCoverFourteenDaysEndingToday() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z"))
        let points = UsageManager.computeCombinedPoints(
            claude: ClaudeUsageData(),
            codex: CodexUsageData(),
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(points.count, 14)
        XCTAssertEqual(points.first?.date, "2026-07-06")
        XCTAssertEqual(points.last?.date, "2026-07-19")
    }

    func testCombinedPointsAggregateDuplicateDatesAndIgnoreFutureWindowShift() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z"))
        var claude = ClaudeUsageData()
        claude.dailyModelTokens = [
            ClaudeDailyModelTokens(date: "2026-07-19", tokensByModel: ["a": 10]),
            ClaudeDailyModelTokens(date: "2026-07-19", tokensByModel: ["b": 15]),
            ClaudeDailyModelTokens(date: "2099-01-01", tokensByModel: ["future": 99])
        ]
        var codex = CodexUsageData()
        codex.dailyUsage = [
            CodexDailyUsage(date: "2026-07-19", sessionCount: 1, tokensUsed: 20),
            CodexDailyUsage(date: "2026-07-19", sessionCount: 2, tokensUsed: 30)
        ]

        let points = UsageManager.computeCombinedPoints(
            claude: claude,
            codex: codex,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(points.last?.date, "2026-07-19")
        XCTAssertEqual(points.last?.claudeTokens, 25)
        XCTAssertEqual(points.last?.codexTokens, 50)
        XCTAssertEqual(points.last?.codexSessions, 3)
    }

    func testTodayUsageRequiresAnExactDateMatch() {
        var codex = CodexUsageData()
        codex.dailyUsage = [
            CodexDailyUsage(date: "2099-01-01", sessionCount: 1, tokensUsed: 100)
        ]

        XCTAssertNil(codex.todayUsage)
        XCTAssertEqual(codex.todayTokens, 0)
    }

    func testApplyResetCreditsParsesAvailableCreditsWithSequentialIndices() {
        let samplePayload: [String: Any] = [
            "availableCount": 2,
            "credits": [
                [
                    "id": "c1",
                    "status": "used",
                    "title": "Used reset"
                ],
                [
                    "id": "c2",
                    "status": "AVAILABLE",
                    "expiresAt": 1785529424.0,
                    "title": "Full reset"
                ],
                [
                    "id": "c3",
                    "status": "available",
                    "expiresAt": 1786557880.0,
                    "title": "Bonus reset"
                ]
            ]
        ]

        var data = CodexUsageData()
        CodexDataReader.shared.applyResetCredits(samplePayload, to: &data)

        XCTAssertEqual(data.availableResetCreditsCount, 2)
        XCTAssertEqual(data.availableResetsCount, 2)
        XCTAssertTrue(data.hasResetsAvailable)
        XCTAssertEqual(data.resets.count, 2)
        XCTAssertEqual(data.resets[0].index, 1)
        XCTAssertEqual(data.resets[0].name, "Full reset")
        XCTAssertEqual(data.resets[1].index, 2)
        XCTAssertEqual(data.resets[1].name, "Bonus reset")
    }
}
