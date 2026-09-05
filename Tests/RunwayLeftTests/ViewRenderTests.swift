import XCTest
import SwiftUI
import AppKit
@testable import RunwayLeft

/// Renders the full popover offscreen with representative data at every text
/// size. Guards against layout code that only fails at runtime, and, when
/// `SNAPSHOT_DIR` is set, writes PNGs there for eyeballing.
final class ViewRenderTests: XCTestCase {
    private var snapshotDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func dateString(daysAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return formatter.string(from: date)
    }

    /// Never touches the network; answers every fetch with an empty error status.
    private final class OfflineStatusService: VendorStatusService {
        override func fetch(_ vendor: StatusVendor, completion: @escaping (VendorStatus) -> Void) {
            var failed = VendorStatus(vendor: vendor)
            failed.fetchedAt = Date()
            failed.errorMessage = "offline (test)"
            completion(failed)
        }
    }

    private var createdSuites: [String] = []

    override func tearDown() {
        for suite in createdSuites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        createdSuites.removeAll()
        super.tearDown()
    }

    private func makeManager(textSize: TextSize, withLiteLLM: Bool = false, healthyStatus: Bool = false) -> UsageManager {
        let suite = "dev.runwayleft.tests.\(UUID().uuidString)"
        createdSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if withLiteLLM {
            // Set before init so the enable flag does not trigger a fetch.
            defaults.set(true, forKey: "liteLLMEnabled")
            defaults.set("http://localhost:4000", forKey: "liteLLMEndpoint")
        }

        let credentials = CredentialStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("runwayleft-render-\(UUID().uuidString)", isDirectory: true))

        // autoStart: false means nothing fetches; status data below is injected directly.
        let manager = UsageManager(defaults: defaults, statusService: OfflineStatusService(), credentialStore: credentials, autoStart: false)
        manager.textSize = textSize

        if withLiteLLM {
            var litellm = LiteLLMUsageData()
            litellm.isConfigured = true
            litellm.endpointHost = "localhost"
            litellm.keyAlias = "developer-1"
            litellm.connection = .connected
            litellm.fetchedAt = Date()
            litellm.spend = 38.2
            litellm.maxBudget = 100
            litellm.budgetResetAt = Calendar.current.date(byAdding: .day, value: 12, to: Date())
            litellm.tpmLimit = 200_000
            litellm.rpmLimit = 60
            litellm.windowDays = 365
            var daily: [LiteLLMDailyUsage] = []
            var perModel: [LiteLLMDailyModelUsage] = []
            for day in 0..<14 {
                let date = dateString(daysAgo: day)
                let spend: Double = 0.4 + Double(day % 4) * 0.3
                let total: Int64 = Int64(35_000 + (day * 9_000) % 60_000)
                daily.append(LiteLLMDailyUsage(date: date, spend: spend, promptTokens: 20_000, completionTokens: 15_000, totalTokens: total, requests: 12 + day % 5))

                let miniTokens: Int64 = Int64(20_000 + (day * 5_000) % 30_000)
                let geminiTokens: Int64 = Int64(15_000 + (day * 4_000) % 30_000)
                perModel.append(LiteLLMDailyModelUsage(date: date, modelName: "gpt-4o-mini", spend: 0.2, tokens: miniTokens, requests: 8))
                perModel.append(LiteLLMDailyModelUsage(date: date, modelName: "gemini-2.5-pro", spend: 0.5, tokens: geminiTokens, requests: 4))
            }
            litellm.daily = daily
            litellm.dailyModelTokens = perModel
            manager.liteLLMData = litellm
        }

        var claude = ClaudeUsageData()
        claude.hasLiveStatus = true
        claude.sessionUsedPct = 8
        claude.sessionReset = "Sep 3 at 5:19pm (Europe/Amsterdam)"
        claude.weekAllModelsPct = 17
        claude.weekAllModelsReset = "Sep 6 at 6:59pm (Europe/Amsterdam)"
        claude.weekFablePct = 72
        claude.weekFableReset = "Sep 6 at 6:59pm (Europe/Amsterdam)"
        claude.weekModelLabel = "Fable"
        claude.totalMessages = 4_812
        claude.totalSessions = 133
        claude.modelUsage = [
            ClaudeModelDetail(modelName: "claude-fable-5-1", inputTokens: 1_200_000, outputTokens: 340_000, cacheReadInputTokens: 9_800_000, cacheCreationInputTokens: 650_000),
            ClaudeModelDetail(modelName: "claude-sonnet-5", inputTokens: 220_000, outputTokens: 80_000, cacheReadInputTokens: 1_100_000, cacheCreationInputTokens: 90_000)
        ]
        claude.dailyActivity = (0..<6).map { ClaudeDailyActivity(date: dateString(daysAgo: $0), messageCount: 40 + $0 * 7, sessionCount: 3, toolCallCount: 120 - $0 * 9) }.reversed()
        claude.dailyModelTokens = (0..<14).map { ClaudeDailyModelTokens(date: dateString(daysAgo: $0), tokensByModel: ["m": Int64(150_000 + ($0 * 37_000) % 400_000)]) }

        var codex = CodexUsageData()
        codex.accountEmail = "someone@example.com"
        codex.accountPlan = "Plus"
        codex.activeModel = "gpt-5.6-sol"
        codex.totalSessions = 212
        codex.totalTokens = 48_300_000
        codex.sessionLimitUsedPct = 63
        codex.sessionLimitResetText = "resets Sep 3 at 8:54 PM"
        codex.weeklyLimitUsedPct = 12
        codex.weeklyLimitResetText = "resets Sep 10 at 2:47 AM"
        codex.availableResetCreditsCount = 1
        codex.resets = [CodexResetItem(index: 1, name: "Full reset", expiryText: "Sep 12")]
        codex.modelBreakdown = [
            CodexModelUsage(modelName: "gpt-5.6-sol", sessionCount: 180, totalTokens: 41_000_000),
            CodexModelUsage(modelName: "o4-mini", sessionCount: 32, totalTokens: 7_300_000)
        ]
        codex.dailyUsage = (0..<14).map { CodexDailyUsage(date: dateString(daysAgo: $0), sessionCount: 2 + $0 % 3, tokensUsed: Int64(90_000 + ($0 * 53_000) % 500_000)) }
        codex.dailyModelTokens = (0..<14).flatMap { day -> [CodexDailyModelTokens] in
            [
                CodexDailyModelTokens(date: dateString(daysAgo: day), modelName: "gpt-5.6-sol", sessionCount: 2, tokens: Int64(70_000 + (day * 41_000) % 400_000)),
                CodexDailyModelTokens(date: dateString(daysAgo: day), modelName: "o4-mini", sessionCount: 1, tokens: Int64(20_000 + (day * 12_000) % 100_000))
            ]
        }

        manager.claudeData = claude
        manager.codexData = codex
        manager.recomputeCombinedPoints()

        // Degraded Anthropic status, healthy OpenAI status.
        let degraded = """
        {
          "page": {"name": "Claude"},
          "components": [
            {"id": "c1", "name": "claude.ai", "status": "degraded_performance", "group": false},
            {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational", "group": false},
            {"id": "c4", "name": "Claude Code", "status": "partial_outage", "group": false}
          ],
          "incidents": [
            {"id": "i1", "name": "Elevated error rates on Claude Code", "status": "monitoring", "impact": "major",
             "shortlink": "https://stspg.io/abc", "updated_at": "2026-09-03T07:45:00.000Z",
             "incident_updates": [{"body": "A fix has been implemented and we are monitoring the results.", "status": "monitoring", "updated_at": "2026-09-03T07:45:00.000Z"}]}
          ],
          "scheduled_maintenances": [],
          "status": {"indicator": "major", "description": "Partial System Outage"}
        }
        """
        let healthy = """
        {
          "page": {"name": "OpenAI"},
          "components": [
            {"id": "o3", "name": "Codex Web", "status": "operational"},
            {"id": "o4", "name": "Codex in ChatGPT Desktop", "status": "operational"},
            {"id": "o5", "name": "Codex API", "status": "operational"},
            {"id": "o6", "name": "VS Code extension", "status": "operational"}
          ],
          "incidents": [], "scheduled_maintenances": [],
          "status": {"indicator": "none", "description": "All Systems Operational"}
        }
        """
        let healthyClaude = """
        {
          "page": {"name": "Claude"},
          "components": [
            {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational", "group": false},
            {"id": "c4", "name": "Claude Code", "status": "operational", "group": false}
          ],
          "incidents": [], "scheduled_maintenances": [],
          "status": {"indicator": "none", "description": "All Systems Operational"}
        }
        """
        manager.claudeStatus = try! VendorStatusService.parse(Data((healthyStatus ? healthyClaude : degraded).utf8), vendor: .claude)
        manager.codexStatus = try! VendorStatusService.parse(Data(healthy.utf8), vendor: .openai)

        return manager
    }

    // MARK: - README screenshots

    /// Set README_SHOTS_DIR to regenerate the images referenced by README.md.
    /// Sample data only, so nothing personal ends up in the repository.
    func testReadmeScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["README_SHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("set README_SHOTS_DIR to write README screenshots")
        }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func save(_ rep: NSBitmapImageRep, _ name: String) throws {
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: dir.appendingPathComponent(name))
        }

        func capture(_ view: some View, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
            let root = ZStack {
                Color(white: 0.14)
                view
            }
            .environment(\.textScale, TextSize.medium.scale)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return rep
        }

        let width = TextSize.medium.popoverWidth
        let manager = makeManager(textSize: .medium, withLiteLLM: true, healthyStatus: true)
        manager.setPopoverHeight(UsageManager.maxPopoverHeightForTests, persist: false)

        // Tabs at their natural height, unclamped: header + content column.
        func tab(_ selected: AppTab, height: CGFloat, name: String) throws {
            manager.selectedTab = selected
            let view = VStack(spacing: 0) {
                HeaderView(manager: manager, selectedTab: .constant(selected))
                Divider().opacity(0.35)
                ScrollView {
                    Group {
                        switch selected {
                        case .overview: OverviewView(manager: manager)
                        case .claude: ClaudeDetailView(manager: manager)
                        case .codex: CodexDetailView(manager: manager)
                        case .models: ModelBreakdownView(manager: manager)
                        case .settings: SettingsView(manager: manager)
                        }
                    }
                    .padding(14)
                }
            }
            try save(try capture(view, width: width, height: height), name)
        }

        try tab(.overview, height: 1_690, name: "overview.png")
        manager.modelsRange = .month
        try tab(.models, height: 1_120, name: "models.png")
        try tab(.claude, height: 1_260, name: "claude.png")
        try tab(.codex, height: 1_330, name: "codex.png")
        manager.liteLLMTest = LiteLLMDataReader.ConnectionTest(
            reachable: .passed("Proxy answers at http://localhost:4000"),
            authenticated: .passed("key “developer-1”, spend $38.20, budget $100"),
            spendTracking: .passed("Daily activity available (today: 35.0K tokens, 12 requests)"),
            state: .connected
        )
        try tab(.settings, height: 2_020, name: "settings.png")

        // Menu bar strip at 3x with an outage on Claude so the outline shows.
        manager.claudeStatus = try VendorStatusService.parse(Data("""
        {"components":[{"id":"c4","name":"Claude Code","status":"partial_outage","group":false}],"incidents":[],"status":{"indicator":"major","description":"Partial System Outage"}}
        """.utf8), vendor: .claude)
        manager.menuBarStyle = .tokensAndQuotas
        let image = manager.menuBarImage
        let scale: CGFloat = 3
        let strip = NSImage(size: NSSize(width: (image.size.width + 24) * scale, height: (image.size.height + 12) * scale))
        strip.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor(white: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: strip.size).fill()
        image.draw(in: NSRect(x: 12 * scale, y: 6 * scale, width: image.size.width * scale, height: image.size.height * scale))
        strip.unlockFocus()
        let tiff = try XCTUnwrap(strip.tiffRepresentation)
        try save(try XCTUnwrap(NSBitmapImageRep(data: tiff)), "menubar.png")
    }

    @discardableResult
    private func render(_ manager: UsageManager, name: String, appearance: NSAppearance.Name = .darkAqua) throws -> NSBitmapImageRep {
        let size = NSSize(width: manager.textSize.popoverWidth, height: manager.popoverHeight)

        // The real popover sits on a vibrancy material. Approximate it with a flat
        // backdrop inside the SwiftUI tree so text anti-aliasing and translucent
        // fills composite correctly in the offscreen capture.
        let backdrop = appearance == .darkAqua
            ? Color(white: 0.16)
            : Color(white: 0.93)
        let root = ZStack {
            backdrop
            MainPopoverView(manager: manager)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.contentView = hosting

        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        XCTAssertGreaterThan(rep.pixelsWide, 0)
        XCTAssertGreaterThan(rep.pixelsHigh, 0)

        if let dir = snapshotDir, let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        }
        return rep
    }

    func testOverviewRendersAtEveryTextSize() throws {
        for size in TextSize.allCases {
            let manager = makeManager(textSize: size)
            manager.selectedTab = .overview
            manager.setPopoverHeight(1_200, persist: false)
            try render(manager, name: "overview-\(size.rawValue)")
        }
    }

    func testOverviewRendersInLightMode() throws {
        let manager = makeManager(textSize: .medium)
        manager.selectedTab = .overview
        manager.setPopoverHeight(1_200, persist: false)
        try render(manager, name: "overview-medium-light", appearance: .aqua)
    }

    func testDetailTabsRender() throws {
        let manager = makeManager(textSize: .medium)
        manager.setPopoverHeight(980, persist: false)

        manager.selectedTab = .claude
        try render(manager, name: "claude-medium")

        manager.selectedTab = .codex
        try render(manager, name: "codex-medium")

        manager.selectedTab = .models
        manager.modelsRange = .week
        try render(manager, name: "models-medium")

        manager.selectedTab = .settings
        try render(manager, name: "settings-medium")
    }

    func testLiteLLMRendersOnOverviewModelsAndSettings() throws {
        // Small width is where a fourth stat card and a third legend entry break first.
        let manager = makeManager(textSize: .small, withLiteLLM: true)
        manager.setPopoverHeight(1_300, persist: false)

        manager.selectedTab = .overview
        try render(manager, name: "overview-small-litellm")

        manager.selectedTab = .models
        manager.modelsRange = .week
        try render(manager, name: "models-small-litellm")

        manager.selectedTab = .settings
        manager.liteLLMTest = LiteLLMDataReader.ConnectionTest(
            reachable: .passed("Proxy answers at http://localhost:4000"),
            authenticated: .passed("key “developer-1”, spend $38.20, budget $100"),
            spendTracking: .failed("This proxy has no database configured, so /key/info and /user/daily/activity are unavailable."),
            state: .noSpendTracking
        )
        try render(manager, name: "settings-small-litellm")

        XCTAssertTrue(manager.combinedDailyPoints.contains { $0.liteLLMTokens > 0 })
        XCTAssertTrue(manager.modelEntries.contains { $0.agent == .litellm })

        // The Settings tab is taller than any screen; host it unclamped to see the LiteLLM section.
        let root = ZStack {
            Color(white: 0.16)
            ScrollView {
                SettingsView(manager: manager)
                    .padding(14)
            }
        }
        .environment(\.textScale, TextSize.small.scale)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: TextSize.small.popoverWidth, height: 2_700)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let dir = snapshotDir, let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: dir.appendingPathComponent("settings-small-litellm-full.png"))
        }
    }

    func testFitModeReportsMeasuredHeight() throws {
        let manager = makeManager(textSize: .medium)
        manager.selectedTab = .overview
        manager.resetPopoverHeight()
        XCTAssertEqual(manager.popoverHeightMode, .fit)

        // Rendering runs the layout pass, which reports the content height.
        try render(manager, name: "overview-fit")
        XCTAssertGreaterThan(manager.fitHeight, UsageManager.minPopoverHeight,
                             "overview content is taller than the minimum, so fit height must grow")
    }

    func testMenuBarImageRendersForEveryStyle() {
        let manager = makeManager(textSize: .medium)
        for style in MenuBarStyle.allCases {
            manager.menuBarStyle = style
            let image = manager.menuBarImage
            XCTAssertGreaterThan(image.size.width, 0, "style \(style)")
            XCTAssertEqual(image.size.height, 18)
        }
        if let dir = snapshotDir {
            // Menu bar composites at 4x on a dark and a light strip, so the glyph is judgeable.
            func save(_ name: String, style: MenuBarStyle, alerts: Bool) {
                manager.menuBarStyle = style
                manager.menuBarStatusAlerts = alerts
                let image = manager.menuBarImage
                let scale: CGFloat = 4
                let strip = NSImage(size: NSSize(width: (image.size.width + 16) * scale, height: image.size.height * scale * 2 + 8 * scale))
                strip.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                NSColor(white: 0.13, alpha: 1).setFill()
                NSRect(x: 0, y: strip.size.height / 2, width: strip.size.width, height: strip.size.height / 2).fill()
                NSColor(white: 0.92, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: strip.size.width, height: strip.size.height / 2).fill()
                let w = image.size.width * scale, h = image.size.height * scale
                image.draw(in: NSRect(x: 8 * scale, y: strip.size.height * 0.75 - h / 2, width: w, height: h))
                image.draw(in: NSRect(x: 8 * scale, y: strip.size.height * 0.25 - h / 2, width: w, height: h))
                strip.unlockFocus()
                if let tiff = strip.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent(name))
                }
            }
            save("menubar-both.png", style: .tokensAndQuotas, alerts: true)
            save("menubar-icononly.png", style: .iconOnly, alerts: false)
            save("menubar-icononly-alert.png", style: .iconOnly, alerts: true)
        }
    }

    func testMenuBarGlyphsLoadFromGeneratedAssets() throws {
        let assets = BrandAssets.shared
        let glyph = try XCTUnwrap(assets.runwayGlyph, "menubar_glyph.png must be present in assets/")
        XCTAssertTrue(glyph.isTemplate)
        XCTAssertEqual(glyph.size, NSSize(width: BrandAssets.menuBarGlyphPointSize, height: BrandAssets.menuBarGlyphPointSize))

        let warning = try XCTUnwrap(assets.runwayWarningGlyph)
        XCTAssertFalse(warning.isTemplate)
        XCTAssertNotNil(assets.appIcon)

        // Glyphs are shapes on a transparent canvas: clear corners, a solid body.
        for candidate in [glyph, warning] {
            let rep = try XCTUnwrap(candidate.representations.first as? NSBitmapImageRep)
            XCTAssertGreaterThan(rep.pixelsWide, Int(BrandAssets.menuBarGlyphPointSize), "glyph carries a high-resolution bitmap")
            let corner = try XCTUnwrap(rep.colorAt(x: 1, y: 1))
            XCTAssertLessThan(corner.alphaComponent, 0.05)

            var opaque = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                    opaque += 1
                }
            }
            let total = rep.pixelsWide * rep.pixelsHigh
            XCTAssertGreaterThan(opaque, total / 50)
            XCTAssertLessThan(opaque, total / 2)
        }
    }
}
