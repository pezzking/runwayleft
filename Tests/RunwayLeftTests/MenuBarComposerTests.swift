import XCTest
@testable import RunwayLeft

final class MenuBarComposerTests: XCTestCase {
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func liveClaude(session: Double = 42, weekAll: Double = 17, weekModel: Double = 32, todayTokens: Int64 = 1_000) -> ClaudeUsageData {
        var claude = ClaudeUsageData()
        claude.hasLiveStatus = true
        claude.sessionUsedPct = session
        claude.weekAllModelsPct = weekAll
        claude.weekFablePct = weekModel
        claude.dailyModelTokens = [ClaudeDailyModelTokens(date: todayString, tokensByModel: ["m": todayTokens])]
        return claude
    }

    private func codexWithWeekly(_ pct: Double? = 17, todayTokens: Int64 = 500) -> CodexUsageData {
        var codex = CodexUsageData()
        codex.weeklyLimitUsedPct = pct
        codex.dailyUsage = [CodexDailyUsage(date: todayString, sessionCount: 1, tokensUsed: todayTokens)]
        return codex
    }

    func testDefaultStyleShowsTokensThenEachVendor() {
        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            options: MenuBarOptions()
        )

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].icon, .app)
        XCTAssertEqual(segments[0].text, "1.5K")
        XCTAssertEqual(segments[1].icon, .claude)
        XCTAssertEqual(segments[1].text, "42%")
        XCTAssertEqual(segments[2].icon, .codex)
        XCTAssertEqual(segments[2].text, "17%")
        XCTAssertTrue(segments.allSatisfy { $0.alert == nil })
    }

    func testIconOnlyStyleIsJustTheBolt() {
        var options = MenuBarOptions()
        options.style = .iconOnly

        let segments = MenuBarComposer.segments(claude: liveClaude(), codex: codexWithWeekly(), options: options)

        XCTAssertEqual(segments, [MenuBarSegment(icon: .app, text: "")])
    }

    func testIconOnlyStillCarriesStatusAlert() {
        var options = MenuBarOptions()
        options.style = .iconOnly

        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            claudeStatus: .operational,
            codexStatus: .majorOutage,
            options: options
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].alert, .majorOutage)
    }

    func testTokensOnlySurfacesAlertOnTheBoltWhenVendorsAreHidden() {
        var options = MenuBarOptions()
        options.style = .tokensOnly

        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            claudeStatus: .degraded,
            codexStatus: nil,
            options: options
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].icon, .app)
        XCTAssertEqual(segments[0].text, "1.5K")
        XCTAssertEqual(segments[0].alert, .degraded)
    }

    func testAlertsAttachToTheAffectedVendorSegment() {
        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            claudeStatus: .operational,
            codexStatus: .partialOutage,
            options: MenuBarOptions()
        )

        XCTAssertNil(segments[0].alert)
        XCTAssertNil(segments[1].alert)
        XCTAssertEqual(segments[2].alert, .partialOutage)
    }

    func testAlertsCanBeDisabled() {
        var options = MenuBarOptions()
        options.showStatusAlerts = false

        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            claudeStatus: .majorOutage,
            codexStatus: .majorOutage,
            options: options
        )

        XCTAssertTrue(segments.allSatisfy { $0.alert == nil })
    }

    func testMaintenanceIsNotAnAlert() {
        let segments = MenuBarComposer.segments(
            claude: liveClaude(),
            codex: codexWithWeekly(),
            claudeStatus: .maintenance,
            codexStatus: .maintenance,
            options: MenuBarOptions()
        )

        XCTAssertTrue(segments.allSatisfy { $0.alert == nil })
    }

    func testQuotasOnlyWithTextLabelsInsteadOfIcons() {
        var options = MenuBarOptions()
        options.style = .quotasOnly
        options.useBrandIcons = false

        let segments = MenuBarComposer.segments(claude: liveClaude(), codex: codexWithWeekly(), options: options)

        XCTAssertEqual(segments.map { $0.icon }, [.none, .none])
        XCTAssertEqual(segments.map { $0.text }, ["C 42%", "X 17%"])
    }

    func testClaudeMetricSelection() {
        let claude = liveClaude(session: 10, weekAll: 55, weekModel: 30)

        XCTAssertEqual(MenuBarComposer.claudeMetricValue(claude, metric: .session), 10)
        XCTAssertEqual(MenuBarComposer.claudeMetricValue(claude, metric: .weekAll), 55)
        XCTAssertEqual(MenuBarComposer.claudeMetricValue(claude, metric: .weekModel), 30)
        XCTAssertEqual(MenuBarComposer.claudeMetricValue(claude, metric: .highest), 55)

        var options = MenuBarOptions()
        options.claudeMetric = .highest
        let segments = MenuBarComposer.segments(claude: claude, codex: codexWithWeekly(), options: options)
        XCTAssertEqual(segments[1].text, "55%")
    }

    func testExpiredClaudeSessionShowsExpiredWhenHistoryExists() {
        var claude = ClaudeUsageData()
        claude.hasLiveStatus = false
        claude.modelUsage = [
            ClaudeModelDetail(modelName: "m", inputTokens: 10, outputTokens: 5, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
        ]

        let segments = MenuBarComposer.segments(claude: claude, codex: codexWithWeekly(nil), options: MenuBarOptions())

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1].icon, .claude)
        XCTAssertEqual(segments[1].text, "Expired")
    }

    func testVendorsWithNoDataAreSkipped() {
        let segments = MenuBarComposer.segments(claude: ClaudeUsageData(), codex: codexWithWeekly(nil), options: MenuBarOptions())

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].icon, .app)
    }

    func testHiddenVendorsAreOmitted() {
        var options = MenuBarOptions()
        options.showClaude = false

        let segments = MenuBarComposer.segments(claude: liveClaude(), codex: codexWithWeekly(), options: options)

        XCTAssertEqual(segments.map { $0.icon }, [.app, .codex])
    }

    func testQuotasOnlyWithEverythingHiddenFallsBackToBolt() {
        var options = MenuBarOptions()
        options.style = .quotasOnly
        options.showClaude = false
        options.showCodex = false

        let segments = MenuBarComposer.segments(claude: liveClaude(), codex: codexWithWeekly(), options: options)

        XCTAssertEqual(segments, [MenuBarSegment(icon: .app, text: "")])
    }

    // MARK: - Popover height clamping

    func testPopoverHeightClampsToMinimumMaximumAndRoundsValues() {
        XCTAssertEqual(UsageManager.clampPopoverHeight(100, screenHeight: 900), UsageManager.minPopoverHeight)
        XCTAssertEqual(UsageManager.clampPopoverHeight(2000, screenHeight: 900), 876)
        XCTAssertEqual(UsageManager.clampPopoverHeight(560.4, screenHeight: 900), 560)
        XCTAssertEqual(UsageManager.clampPopoverHeight(.nan, screenHeight: 900), UsageManager.defaultPopoverHeight)
        XCTAssertEqual(UsageManager.clampPopoverHeight(500, screenHeight: 300), UsageManager.minPopoverHeight)
    }
}
