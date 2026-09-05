import Foundation
import Combine
import AppKit
import ServiceManagement

enum PopoverHeightMode: String, CaseIterable, Identifiable {
    case fit
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit: return "Fit content"
        case .custom: return "Custom"
        }
    }
}

class UsageManager: ObservableObject {
    static let shared = UsageManager()

    private enum Keys {
        static let refreshInterval = "refreshIntervalSeconds"
        static let legacyShowQuota = "showQuotaInMenuBar"
        static let textSize = "textSize"
        static let popoverHeight = "popoverHeight"
        static let popoverHeightMode = "popoverHeightMode"
        static let lastFitHeight = "lastFitHeight"
        static let menuBarStyle = "menuBarStyle"
        static let claudeMenuMetric = "claudeMenuMetric"
        static let codexMenuMetric = "codexMenuMetric"
        static let showClaudeInMenuBar = "showClaudeInMenuBar"
        static let showCodexInMenuBar = "showCodexInMenuBar"
        static let menuBarBrandIcons = "menuBarBrandIcons"
        static let menuBarStatusAlerts = "menuBarStatusAlerts"
        static let vendorStatusEnabled = "vendorStatusEnabled"
        static let modelsRange = "modelsRange"
        static let liteLLMEnabled = "liteLLMEnabled"
        static let liteLLMEndpoint = "liteLLMEndpoint"
        static let showLiteLLMInMenuBar = "showLiteLLMInMenuBar"
        static let legacyMigrated = "migratedFromAIUsageTracker"

        /// Every key worth carrying over from the pre-rename defaults domain.
        /// The LiteLLM API key is never in defaults; see `CredentialStore`.
        static let persisted: [String] = [
            refreshInterval, legacyShowQuota, textSize, popoverHeight, popoverHeightMode, lastFitHeight,
            menuBarStyle, claudeMenuMetric, codexMenuMetric, showClaudeInMenuBar, showCodexInMenuBar,
            menuBarBrandIcons, menuBarStatusAlerts, vendorStatusEnabled, modelsRange,
            liteLLMEnabled, liteLLMEndpoint, showLiteLLMInMenuBar
        ]
    }

    /// Bundle identifier the app shipped under before it was renamed to RunwayLeft.
    static let legacyBundleIdentifier = "dev.aiusagetracker.app"

    /// One-time copy of settings from the old defaults domain, so the rename
    /// does not reset anyone's preferences. Runs only for the standard domain.
    static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard defaults.object(forKey: Keys.legacyMigrated) == nil else { return }
        defaults.set(true, forKey: Keys.legacyMigrated)

        guard Bundle.main.bundleIdentifier != legacyBundleIdentifier,
              let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier),
              !legacy.isEmpty else { return }

        for key in Keys.persisted where defaults.object(forKey: key) == nil {
            if let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    // MARK: - Usage Data

    @Published var claudeData = ClaudeUsageData()
    @Published var codexData = CodexUsageData()
    @Published var combinedDailyPoints: [CombinedDailyPoint] = []
    @Published var lastRefreshed: Date = Date()
    @Published var isRefreshing: Bool = false
    @Published var selectedTab: AppTab = .overview

    // MARK: - Provider Status

    @Published var claudeStatus = VendorStatus(vendor: .claude)
    @Published var codexStatus = VendorStatus(vendor: .openai)
    @Published var isCheckingStatus: Bool = false

    /// Status pages are polled at most this often, whatever the refresh interval.
    /// The Refresh button bypasses the throttle.
    static let statusFetchMinimumInterval: TimeInterval = 300
    private var lastStatusFetch: Date?
    private let statusService: VendorStatusService

    // MARK: - LiteLLM

    @Published var liteLLMData = LiteLLMUsageData()
    @Published var isFetchingLiteLLM: Bool = false
    @Published var liteLLMTest: LiteLLMDataReader.ConnectionTest? = nil
    @Published var isTestingLiteLLM: Bool = false

    static let liteLLMFetchMinimumInterval: TimeInterval = 300
    private var lastLiteLLMFetch: Date?
    private let liteLLMReader: LiteLLMDataReader
    private let credentialStore: CredentialStore

    @Published var liteLLMEnabled: Bool = false {
        didSet {
            defaults.set(liteLLMEnabled, forKey: Keys.liteLLMEnabled)
            if liteLLMEnabled {
                refreshLiteLLM(force: true)
            } else {
                liteLLMData = LiteLLMUsageData()
                recomputeCombinedPoints()
            }
        }
    }

    @Published var liteLLMEndpoint: String = "" {
        didSet {
            defaults.set(liteLLMEndpoint, forKey: Keys.liteLLMEndpoint)
            liteLLMTest = nil
        }
    }

    /// Kept in memory and in a 0600 file under Application Support, never in defaults.
    @Published var liteLLMAPIKey: String = "" {
        didSet {
            credentialStore.save(liteLLMAPIKey, as: CredentialStore.liteLLMKeyFile)
            liteLLMTest = nil
        }
    }

    @Published var showLiteLLMInMenuBar: Bool = true {
        didSet { defaults.set(showLiteLLMInMenuBar, forKey: Keys.showLiteLLMInMenuBar) }
    }

    var liteLLMConfig: LiteLLMDataReader.Config? {
        guard liteLLMEnabled else { return nil }
        return LiteLLMDataReader.Config(endpoint: liteLLMEndpoint, apiKey: liteLLMAPIKey)
    }

    /// Polls the proxy on its own path, throttled like the status pages.
    func refreshLiteLLM(force: Bool = false) {
        guard liteLLMEnabled else { return }
        guard let config = liteLLMConfig else {
            var data = LiteLLMUsageData()
            data.connection = .notConfigured
            liteLLMData = data
            return
        }
        if !force, let last = lastLiteLLMFetch, Date().timeIntervalSince(last) < Self.liteLLMFetchMinimumInterval {
            return
        }
        guard !isFetchingLiteLLM else { return }

        isFetchingLiteLLM = true
        lastLiteLLMFetch = Date()

        liteLLMReader.fetch(config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.liteLLMEnabled, self.liteLLMConfig == config {
                    self.liteLLMData = result
                    self.recomputeCombinedPoints()
                }
                self.isFetchingLiteLLM = false
            }
        }
    }

    /// Settings "Test connection": three stages reported separately.
    func testLiteLLMConnection() {
        guard let config = LiteLLMDataReader.Config(endpoint: liteLLMEndpoint, apiKey: liteLLMAPIKey) else {
            liteLLMTest = LiteLLMDataReader.ConnectionTest(
                reachable: .failed("Enter an endpoint URL and an API key first."),
                state: .notConfigured
            )
            return
        }
        guard !isTestingLiteLLM else { return }
        isTestingLiteLLM = true
        liteLLMReader.testConnection(config: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.liteLLMTest = result
                self.isTestingLiteLLM = false
                if result.state == .connected, self.liteLLMEnabled {
                    self.refreshLiteLLM(force: true)
                }
            }
        }
    }

    func statusLevelForLiteLLM() -> StatusLevel? {
        guard liteLLMEnabled, liteLLMData.isConfigured, liteLLMData.fetchedAt != nil else { return nil }
        return liteLLMData.connection.level
    }

    // MARK: - Settings

    @Published var refreshIntervalSeconds: Double = 60.0 {
        didSet {
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshInterval)
            setupTimer()
        }
    }

    @Published var textSize: TextSize = .medium {
        didSet { defaults.set(textSize.rawValue, forKey: Keys.textSize) }
    }

    @Published var popoverHeightMode: PopoverHeightMode = .fit {
        didSet { defaults.set(popoverHeightMode.rawValue, forKey: Keys.popoverHeightMode) }
    }

    /// User-chosen height, used in `.custom` mode.
    @Published private(set) var popoverHeight: CGFloat = UsageManager.defaultPopoverHeight

    /// Last measured content height, used in `.fit` mode.
    @Published private(set) var fitHeight: CGFloat = UsageManager.defaultPopoverHeight

    @Published var menuBarStyle: MenuBarStyle = .tokensAndQuotas {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    @Published var claudeMenuMetric: ClaudeMenuMetric = .session {
        didSet { defaults.set(claudeMenuMetric.rawValue, forKey: Keys.claudeMenuMetric) }
    }

    @Published var codexMenuMetric: CodexMenuMetric = .session {
        didSet { defaults.set(codexMenuMetric.rawValue, forKey: Keys.codexMenuMetric) }
    }

    @Published var showClaudeInMenuBar: Bool = true {
        didSet { defaults.set(showClaudeInMenuBar, forKey: Keys.showClaudeInMenuBar) }
    }

    @Published var showCodexInMenuBar: Bool = true {
        didSet { defaults.set(showCodexInMenuBar, forKey: Keys.showCodexInMenuBar) }
    }

    @Published var menuBarBrandIcons: Bool = true {
        didSet { defaults.set(menuBarBrandIcons, forKey: Keys.menuBarBrandIcons) }
    }

    @Published var menuBarStatusAlerts: Bool = true {
        didSet { defaults.set(menuBarStatusAlerts, forKey: Keys.menuBarStatusAlerts) }
    }

    @Published var vendorStatusEnabled: Bool = true {
        didSet {
            defaults.set(vendorStatusEnabled, forKey: Keys.vendorStatusEnabled)
            if vendorStatusEnabled {
                refreshVendorStatus(force: true)
            } else {
                claudeStatus = VendorStatus(vendor: .claude)
                codexStatus = VendorStatus(vendor: .openai)
            }
        }
    }

    @Published var modelsRange: UsageRange = .all {
        didSet { defaults.set(modelsRange.rawValue, forKey: Keys.modelsRange) }
    }

    // MARK: - Launch at Login

    @Published private(set) var launchAtLogin: Bool = false
    @Published private(set) var launchAtLoginNote: String? = nil

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        switch status {
        case .requiresApproval:
            launchAtLoginNote = "Waiting for approval in System Settings › General › Login Items."
        default:
            launchAtLoginNote = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginNote = "Couldn't change login item: \(error.localizedDescription)"
        }
    }

    // MARK: - Popover Sizing

    static let defaultPopoverHeight: CGFloat = 560
    static let minPopoverHeight: CGFloat = 400

    /// Keeps the popover between the minimum height and what fits on screen.
    static func clampPopoverHeight(_ height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let maxHeight = max(minPopoverHeight, screenHeight - 24)
        let rounded = height.isFinite ? height.rounded() : defaultPopoverHeight
        return min(max(rounded, minPopoverHeight), maxHeight)
    }

    static var currentScreenHeight: CGFloat {
        NSScreen.main?.visibleFrame.height ?? 900
    }

    var maxPopoverHeight: CGFloat {
        max(Self.minPopoverHeight, Self.currentScreenHeight - 24)
    }

    /// Tallest height the current screen allows; used by offscreen renders.
    static var maxPopoverHeightForTests: CGFloat {
        max(minPopoverHeight, currentScreenHeight - 24)
    }

    /// The height the popover frame should use right now.
    var effectivePopoverHeight: CGFloat {
        let target = popoverHeightMode == .fit ? fitHeight : popoverHeight
        return Self.clampPopoverHeight(target, screenHeight: Self.currentScreenHeight)
    }

    /// Called by the root view whenever the current tab's natural height changes.
    func reportFitHeight(_ height: CGFloat) {
        let clamped = Self.clampPopoverHeight(height, screenHeight: Self.currentScreenHeight)
        guard clamped != fitHeight else { return }
        fitHeight = clamped
        defaults.set(Double(clamped), forKey: Keys.lastFitHeight)
    }

    /// Sets a custom height (switching to `.custom` mode if needed).
    func setPopoverHeight(_ height: CGFloat, persist: Bool = true) {
        let clamped = Self.clampPopoverHeight(height, screenHeight: Self.currentScreenHeight)
        if popoverHeightMode != .custom {
            popoverHeightMode = .custom
        }
        if clamped != popoverHeight {
            popoverHeight = clamped
        }
        if persist {
            defaults.set(Double(clamped), forKey: Keys.popoverHeight)
        }
    }

    /// Returns to fit-to-content sizing.
    func resetPopoverHeight() {
        popoverHeightMode = .fit
    }

    // MARK: - Lifecycle

    private let defaults: UserDefaults
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        statusService: VendorStatusService = .shared,
        liteLLMReader: LiteLLMDataReader = LiteLLMDataReader(),
        credentialStore: CredentialStore = CredentialStore(),
        autoStart: Bool = true
    ) {
        self.defaults = defaults
        self.statusService = statusService
        self.liteLLMReader = liteLLMReader
        self.credentialStore = credentialStore

        if defaults === UserDefaults.standard {
            Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        }

        _liteLLMEnabled = Published(initialValue: defaults.object(forKey: Keys.liteLLMEnabled) as? Bool ?? false)
        _liteLLMEndpoint = Published(initialValue: defaults.string(forKey: Keys.liteLLMEndpoint) ?? "")
        _liteLLMAPIKey = Published(initialValue: credentialStore.load(CredentialStore.liteLLMKeyFile) ?? "")
        _showLiteLLMInMenuBar = Published(initialValue: defaults.object(forKey: Keys.showLiteLLMInMenuBar) as? Bool ?? true)

        // Assign through the `Published` backing storage: setting the wrapped
        // properties here would run their `didSet` observers (they are computed
        // properties), which would write defaults back and start a status fetch
        // mid-initialization.
        _refreshIntervalSeconds = Published(initialValue: defaults.object(forKey: Keys.refreshInterval) as? Double ?? 60.0)

        if let raw = defaults.string(forKey: Keys.textSize), let size = TextSize(rawValue: raw) {
            _textSize = Published(initialValue: size)
        }

        if let raw = defaults.string(forKey: Keys.popoverHeightMode), let mode = PopoverHeightMode(rawValue: raw) {
            _popoverHeightMode = Published(initialValue: mode)
        }

        if let saved = defaults.object(forKey: Keys.popoverHeight) as? Double {
            _popoverHeight = Published(initialValue: Self.clampPopoverHeight(CGFloat(saved), screenHeight: Self.currentScreenHeight))
        }

        if let saved = defaults.object(forKey: Keys.lastFitHeight) as? Double {
            _fitHeight = Published(initialValue: Self.clampPopoverHeight(CGFloat(saved), screenHeight: Self.currentScreenHeight))
        }

        if let raw = defaults.string(forKey: Keys.menuBarStyle), let style = MenuBarStyle(rawValue: raw) {
            _menuBarStyle = Published(initialValue: style)
        } else if defaults.object(forKey: Keys.legacyShowQuota) as? Bool == false {
            // Users who had turned quotas off before the style picker existed.
            _menuBarStyle = Published(initialValue: .tokensOnly)
            defaults.set(MenuBarStyle.tokensOnly.rawValue, forKey: Keys.menuBarStyle)
        }

        if let raw = defaults.string(forKey: Keys.claudeMenuMetric), let metric = ClaudeMenuMetric(rawValue: raw) {
            _claudeMenuMetric = Published(initialValue: metric)
        }

        if let raw = defaults.string(forKey: Keys.codexMenuMetric), let metric = CodexMenuMetric(rawValue: raw) {
            _codexMenuMetric = Published(initialValue: metric)
        }

        if let raw = defaults.string(forKey: Keys.modelsRange), let range = UsageRange(rawValue: raw) {
            _modelsRange = Published(initialValue: range)
        }

        _showClaudeInMenuBar = Published(initialValue: defaults.object(forKey: Keys.showClaudeInMenuBar) as? Bool ?? true)
        _showCodexInMenuBar = Published(initialValue: defaults.object(forKey: Keys.showCodexInMenuBar) as? Bool ?? true)
        _menuBarBrandIcons = Published(initialValue: defaults.object(forKey: Keys.menuBarBrandIcons) as? Bool ?? true)
        _menuBarStatusAlerts = Published(initialValue: defaults.object(forKey: Keys.menuBarStatusAlerts) as? Bool ?? true)
        _vendorStatusEnabled = Published(initialValue: defaults.object(forKey: Keys.vendorStatusEnabled) as? Bool ?? true)

        if autoStart {
            refreshLaunchAtLoginStatus()
            refreshData()
            setupTimer()
        }
    }

    // MARK: - Refresh

    /// Re-reads local usage. Live quota checks (the `claude` CLI, the Codex
    /// app-server) and status pages are throttled to every few minutes; pass
    /// `force: true` from the Refresh button to bypass that.
    func refreshData(force: Bool = false) {
        refreshVendorStatus(force: force)
        refreshLiteLLM(force: force)

        guard !isRefreshing else { return }
        isRefreshing = true

        // The readers keep incremental caches; this queue is their only caller.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let claude = ClaudeDataReader.shared.fetchUsageData(forceLive: force)
            let codex = CodexDataReader.shared.fetchUsageData(forceLive: force)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.claudeData = claude
                self.codexData = codex
                self.recomputeCombinedPoints()
                self.lastRefreshed = Date()
                self.isRefreshing = false
            }
        }
    }

    /// The chart derives from all three sources, each of which arrives on its
    /// own schedule, so it is recomputed whenever any of them lands.
    func recomputeCombinedPoints() {
        combinedDailyPoints = Self.computeCombinedPoints(
            claude: claudeData,
            codex: codexData,
            litellm: liteLLMEnabled ? liteLLMData : LiteLLMUsageData()
        )
    }

    /// Polls both status pages on their own background path so a slow network
    /// never delays the local quota numbers.
    func refreshVendorStatus(force: Bool = false) {
        guard vendorStatusEnabled else { return }
        if !force, let last = lastStatusFetch, Date().timeIntervalSince(last) < Self.statusFetchMinimumInterval {
            return
        }
        guard !isCheckingStatus else { return }

        isCheckingStatus = true
        lastStatusFetch = Date()

        let group = DispatchGroup()
        var claudeResult: VendorStatus?
        var codexResult: VendorStatus?

        group.enter()
        statusService.fetch(.claude) { result in
            claudeResult = result
            group.leave()
        }

        group.enter()
        statusService.fetch(.openai) { result in
            codexResult = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if self.vendorStatusEnabled {
                if let claude = claudeResult { self.claudeStatus = claude }
                if let codex = codexResult { self.codexStatus = codex }
            }
            self.isCheckingStatus = false
        }
    }

    private func setupTimer() {
        timer?.invalidate()
        guard refreshIntervalSeconds > 0 else { return }
        let refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
        // Let the system coalesce our wakeups with others; saves power.
        refreshTimer.tolerance = refreshIntervalSeconds * 0.1
        timer = refreshTimer
    }

    // MARK: - Derived Data

    static func computeCombinedPoints(
        claude: ClaudeUsageData,
        codex: CodexUsageData,
        litellm: LiteLLMUsageData = LiteLLMUsageData(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CombinedDailyPoint] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var claudeTokensMap: [String: Int64] = [:]
        var claudeSessionsMap: [String: Int] = [:]
        var codexTokensMap: [String: Int64] = [:]
        var codexSessionsMap: [String: Int] = [:]
        var litellmTokensMap: [String: Int64] = [:]

        for item in claude.dailyModelTokens {
            claudeTokensMap[item.date, default: 0] += item.totalTokens
        }
        for item in claude.dailyActivity {
            claudeSessionsMap[item.date, default: 0] += item.sessionCount
        }
        for item in codex.dailyUsage {
            codexTokensMap[item.date, default: 0] += item.tokensUsed
            codexSessionsMap[item.date, default: 0] += item.sessionCount
        }
        for item in litellm.daily {
            litellmTokensMap[item.date, default: 0] += item.totalTokens
        }

        // Generate the last 14 calendar dates. Future-dated or malformed cache
        // entries must not shift the visible window away from today.
        var recentDates: [String] = []
        for dayOffset in (0..<14).reversed() {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                recentDates.append(formatter.string(from: date))
            }
        }

        return recentDates.map { date in
            CombinedDailyPoint(
                date: date,
                codexTokens: codexTokensMap[date] ?? 0,
                claudeTokens: claudeTokensMap[date] ?? 0,
                codexSessions: codexSessionsMap[date] ?? 0,
                claudeSessions: claudeSessionsMap[date] ?? 0,
                liteLLMTokens: litellmTokensMap[date] ?? 0
            )
        }
    }

    var modelEntries: [ModelUsageEntry] {
        ModelUsageAggregator.entries(
            claude: claudeData,
            codex: codexData,
            litellm: liteLLMEnabled ? liteLLMData : LiteLLMUsageData(),
            range: modelsRange
        )
    }

    static func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.2fB", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Menu Bar

    var menuBarOptions: MenuBarOptions {
        MenuBarOptions(
            style: menuBarStyle,
            claudeMetric: claudeMenuMetric,
            codexMetric: codexMenuMetric,
            showClaude: showClaudeInMenuBar,
            showCodex: showCodexInMenuBar,
            showLiteLLM: showLiteLLMInMenuBar,
            useBrandIcons: menuBarBrandIcons,
            showStatusAlerts: menuBarStatusAlerts
        )
    }

    /// Effective status level for menu bar alerts; nil when polling is off or nothing loaded yet.
    func statusLevel(for status: VendorStatus) -> StatusLevel? {
        guard vendorStatusEnabled, status.isLoaded else { return nil }
        return status.effectiveLevel
    }

    var menuBarSegments: [MenuBarSegment] {
        MenuBarComposer.segments(
            claude: claudeData,
            codex: codexData,
            litellm: liteLLMEnabled ? liteLLMData : LiteLLMUsageData(),
            claudeStatus: statusLevel(for: claudeStatus),
            codexStatus: statusLevel(for: codexStatus),
            liteLLMStatus: statusLevelForLiteLLM(),
            options: menuBarOptions
        )
    }

    private var cachedMenuBarImage: NSImage?
    private var cachedMenuBarSegments: [MenuBarSegment] = []
    private var cachedMenuBarAppearance: String = ""

    /// The App body re-evaluates on every published change (tab switches,
    /// refresh flags, height), so the image is only re-rasterized when the
    /// segments or the appearance actually change.
    var menuBarImage: NSImage {
        let segments = menuBarSegments
        let appearance = NSApp?.effectiveAppearance.name.rawValue ?? ""
        if let cached = cachedMenuBarImage, segments == cachedMenuBarSegments, appearance == cachedMenuBarAppearance {
            return cached
        }
        let image = BrandAssets.shared.createMenuBarImage(segments: segments)
        cachedMenuBarImage = image
        cachedMenuBarSegments = segments
        cachedMenuBarAppearance = appearance
        return image
    }
}
