import XCTest
@testable import RunwayLeft

final class CodexRateLimitTests: XCTestCase {
    func testWindowsAreClassifiedByDuration() {
        XCTAssertEqual(CodexDataReader.classifyWindow(minutes: 300), .session)
        XCTAssertEqual(CodexDataReader.classifyWindow(minutes: 10_080), .weekly)
        XCTAssertEqual(CodexDataReader.classifyWindow(minutes: 20_160), .weekly)
        XCTAssertEqual(CodexDataReader.classifyWindow(minutes: nil), .unknown)
        XCTAssertEqual(CodexDataReader.classifyWindow(minutes: 0), .unknown)
    }

    func testLiveRateLimitsFillBothSlots() {
        // Shape captured from `codex app-server` account/rateLimits/read.
        let limits: [String: Any] = [
            "limitId": "codex",
            "primary": ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1_788_484_033],
            "secondary": ["usedPercent": 2, "windowDurationMins": 10_080, "resetsAt": 1_789_070_833],
            "planType": "plus"
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data)

        XCTAssertEqual(data.sessionLimitUsedPct, 10)
        XCTAssertEqual(data.weeklyLimitUsedPct, 2)
        XCTAssertTrue(data.sessionLimitResetText.hasPrefix("resets "))
        XCTAssertTrue(data.weeklyLimitResetText.hasPrefix("resets "))
        XCTAssertEqual(data.accountPlan, "Plus")
        XCTAssertTrue(data.hasRateLimits)
    }

    func testUnknownDurationFillsWeeklyFirstThenSession() {
        var data = CodexUsageData()
        CodexDataReader.applyRateLimitWindow(usedPercent: 40, resetsAt: nil, minutes: nil, to: &data)
        XCTAssertEqual(data.weeklyLimitUsedPct, 40)
        XCTAssertNil(data.sessionLimitUsedPct)

        CodexDataReader.applyRateLimitWindow(usedPercent: 60, resetsAt: nil, minutes: nil, to: &data)
        XCTAssertEqual(data.weeklyLimitUsedPct, 40)
        XCTAssertEqual(data.sessionLimitUsedPct, 60)
    }

    func testPercentagesAreClamped() {
        var data = CodexUsageData()
        CodexDataReader.applyRateLimitWindow(usedPercent: 140, resetsAt: nil, minutes: 300, to: &data)
        CodexDataReader.applyRateLimitWindow(usedPercent: -5, resetsAt: nil, minutes: 10_080, to: &data)
        XCTAssertEqual(data.sessionLimitUsedPct, 100)
        XCTAssertEqual(data.weeklyLimitUsedPct, 0)
    }

    func testMenuBarCodexMetricSelection() {
        var codex = CodexUsageData()
        codex.sessionLimitUsedPct = 10
        codex.weeklyLimitUsedPct = 2

        XCTAssertEqual(MenuBarComposer.codexMetricValue(codex, metric: .session), 10)
        XCTAssertEqual(MenuBarComposer.codexMetricValue(codex, metric: .weekly), 2)
        XCTAssertEqual(MenuBarComposer.codexMetricValue(codex, metric: .highest), 10)

        var weeklyOnly = CodexUsageData()
        weeklyOnly.weeklyLimitUsedPct = 17
        XCTAssertEqual(MenuBarComposer.codexMetricValue(weeklyOnly, metric: .session), 17, "falls back to the window that exists")

        var options = MenuBarOptions()
        options.codexMetric = .weekly
        let segments = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: codex, options: options)
        XCTAssertEqual(segments.last?.icon, .codex)
        XCTAssertEqual(segments.last?.text, "2%")
    }
}
