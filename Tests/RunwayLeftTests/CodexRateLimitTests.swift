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
        // Shape captured from `codex app-server` account/rateLimits/read on 2026-09-08.
        let limits: [String: Any] = [
            "limitId": "codex",
            "limitName": NSNull(),
            "primary": ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1_788_862_494],
            "secondary": ["usedPercent": 2, "windowDurationMins": 10_080, "resetsAt": 1_789_449_294],
            "credits": ["hasCredits": false, "unlimited": false, "balance": "0"],
            "individualLimit": NSNull(),
            "spendControlReached": false,
            "planType": "plus",
            "rateLimitReachedType": NSNull()
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

    func testSessionLogFieldNamesAreAccepted() {
        // Shape of `payload.rate_limits` in ~/.codex/sessions/*.jsonl.
        let limits: [String: Any] = [
            "primary": ["used_percent": 12.5, "window_minutes": 300, "resets_at": 1_788_862_494],
            "secondary": ["used_percent": 63.5, "window_minutes": 10_080, "resets_at": 1_789_449_294]
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data)

        XCTAssertEqual(data.sessionLimitUsedPct, 12.5)
        XCTAssertEqual(data.weeklyLimitUsedPct, 63.5)
        XCTAssertTrue(data.sessionLimitResetText.hasPrefix("resets "))
    }

    func testWeeklyWindowAloneUnderPrimaryIsNotMistakenForSession() {
        // Verbatim from a real session log: the weekly window is the only one, and it sits in `primary`.
        let limits: [String: Any] = [
            "limit_id": "codex",
            "primary": ["used_percent": 4.0, "window_minutes": 10_080, "resets_at": 1_788_155_737],
            "secondary": NSNull(),
            "plan_type": "plus"
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data)

        XCTAssertEqual(data.weeklyLimitUsedPct, 4)
        XCTAssertNil(data.sessionLimitUsedPct)
    }

    func testDurationBeatsPositionWhenTheyDisagree() {
        let limits: [String: Any] = [
            "primary": ["usedPercent": 70, "windowDurationMins": 10_080],
            "secondary": ["usedPercent": 20, "windowDurationMins": 300]
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data)

        XCTAssertEqual(data.sessionLimitUsedPct, 20)
        XCTAssertEqual(data.weeklyLimitUsedPct, 70)
    }

    func testUnknownDurationFallsBackToPosition() {
        let limits: [String: Any] = [
            "primary": ["usedPercent": 40],
            "secondary": ["usedPercent": 60]
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data)

        XCTAssertEqual(data.sessionLimitUsedPct, 40, "primary is the 5-hour window when nothing says otherwise")
        XCTAssertEqual(data.weeklyLimitUsedPct, 60)
    }

    func testOnlyIfMissingKeepsLiveValues() {
        var data = CodexUsageData()
        data.weeklyLimitUsedPct = 2
        data.weeklyLimitResetText = "resets live"

        let logged: [String: Any] = [
            "primary": ["used_percent": 55, "window_minutes": 300, "resets_at": 1_788_862_494],
            "secondary": ["used_percent": 90, "window_minutes": 10_080, "resets_at": 1_789_449_294]
        ]
        CodexDataReader.applyRateLimits(logged, to: &data, onlyIfMissing: true)

        XCTAssertEqual(data.sessionLimitUsedPct, 55, "the missing window is filled")
        XCTAssertEqual(data.weeklyLimitUsedPct, 2, "the live window is kept")
        XCTAssertEqual(data.weeklyLimitResetText, "resets live")
    }

    func testExpiredWindowIsSkipped() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let limits: [String: Any] = [
            "primary": ["used_percent": 80, "window_minutes": 300, "resets_at": now.timeIntervalSince1970 - 60],
            "secondary": ["used_percent": 30, "window_minutes": 10_080, "resets_at": now.timeIntervalSince1970 + 3600]
        ]

        var data = CodexUsageData()
        CodexDataReader.applyRateLimits(limits, to: &data, expiredBefore: now)

        XCTAssertNil(data.sessionLimitUsedPct, "a window that has already reset says nothing about the current one")
        XCTAssertEqual(data.weeklyLimitUsedPct, 30)
    }

    func testPercentagesAreClamped() {
        var data = CodexUsageData()
        CodexDataReader.applyRateLimitWindow(usedPercent: 140, resetsAt: nil, minutes: 300, positionalSlot: .session, to: &data)
        CodexDataReader.applyRateLimitWindow(usedPercent: -5, resetsAt: nil, minutes: 10_080, positionalSlot: .weekly, to: &data)
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

    // MARK: - Session-log fallback against real files

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runwayleft-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("sessions/2026/09/08"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    private func writeSessionLog(_ lines: [[String: Any]], named name: String = "rollout.jsonl") throws {
        let text = try lines.map { line -> String in
            let data = try JSONSerialization.data(withJSONObject: ["type": "event_msg", "payload": line])
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try text.write(to: tempDir.appendingPathComponent("sessions/2026/09/08/\(name)"), atomically: true, encoding: .utf8)
    }

    private func reader() -> CodexDataReader {
        CodexDataReader(customPath: tempDir.appendingPathComponent("state_5.sqlite").path)
    }

    func testSessionLogsFillOnlyTheMissingWindowAndSkipEmptyLines() throws {
        let now = Date()
        let epoch = now.timeIntervalSince1970
        try writeSessionLog([
            ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": 33, "window_minutes": 300, "resets_at": epoch + 2 * 3600],
                "secondary": ["used_percent": 41, "window_minutes": 10_080, "resets_at": epoch + 5 * 86_400]
            ]],
            // Newest first when read: the weekly window alone, then a line with both windows null.
            ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": 4, "window_minutes": 10_080, "resets_at": epoch + 3 * 86_400],
                "secondary": NSNull()
            ]],
            ["type": "token_count", "rate_limits": ["primary": NSNull(), "secondary": NSNull()]]
        ])

        var data = CodexUsageData()
        reader().fillRateLimitsFromSessionLogs(into: &data, now: now)

        XCTAssertEqual(data.weeklyLimitUsedPct, 4, "newest line that has the window wins")
        XCTAssertEqual(data.sessionLimitUsedPct, 33, "the 5-hour window comes from the older line")
    }

    func testSessionLogsNeverOverwriteLiveWindows() throws {
        let epoch = Date().timeIntervalSince1970
        try writeSessionLog([
            ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": 33, "window_minutes": 300, "resets_at": epoch + 2 * 3600],
                "secondary": ["used_percent": 41, "window_minutes": 10_080, "resets_at": epoch + 5 * 86_400]
            ]]
        ])

        var data = CodexUsageData()
        data.weeklyLimitUsedPct = 2
        reader().fillRateLimitsFromSessionLogs(into: &data)

        XCTAssertEqual(data.weeklyLimitUsedPct, 2)
        XCTAssertEqual(data.sessionLimitUsedPct, 33)
    }

    func testSessionLogsIgnoreWindowsThatAlreadyReset() throws {
        let now = Date()
        let epoch = now.timeIntervalSince1970
        try writeSessionLog([
            ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": 80, "window_minutes": 300, "resets_at": epoch - 3600],
                "secondary": ["used_percent": 41, "window_minutes": 10_080, "resets_at": epoch + 5 * 86_400]
            ]]
        ])

        var data = CodexUsageData()
        reader().fillRateLimitsFromSessionLogs(into: &data, now: now)

        XCTAssertNil(data.sessionLimitUsedPct)
        XCTAssertEqual(data.weeklyLimitUsedPct, 41)
    }

    func testSessionLogsOlderThanTheWindowAreNotOpened() throws {
        let epoch = Date().timeIntervalSince1970
        try writeSessionLog([
            ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": 33, "window_minutes": 300, "resets_at": epoch + 2 * 3600]
            ]]
        ])
        // Backdate the file past the 5-hour window; only the session slot is missing.
        let file = tempDir.appendingPathComponent("sessions/2026/09/08/rollout.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -6 * 3600)], ofItemAtPath: file.path)

        var data = CodexUsageData()
        data.weeklyLimitUsedPct = 2
        reader().fillRateLimitsFromSessionLogs(into: &data)

        XCTAssertNil(data.sessionLimitUsedPct)
    }
}
