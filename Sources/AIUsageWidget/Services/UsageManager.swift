import Foundation
import Combine

class UsageManager: ObservableObject {
    static let shared = UsageManager()
    
    @Published var claudeData = ClaudeUsageData()
    @Published var codexData = CodexUsageData()
    @Published var combinedDailyPoints: [CombinedDailyPoint] = []
    @Published var lastRefreshed: Date = Date()
    @Published var isRefreshing: Bool = false
    @Published var selectedTab: AppTab = .overview
    
    @Published var refreshIntervalSeconds: Double = 60.0 {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: "refreshIntervalSeconds")
            setupTimer()
        }
    }
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let savedRefreshInterval = UserDefaults.standard.object(forKey: "refreshIntervalSeconds") as? Double ?? 60.0
        self.refreshIntervalSeconds = savedRefreshInterval
        
        refreshData()
        setupTimer()
    }
    
    func refreshData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let claude = ClaudeDataReader.shared.fetchUsageData()
            let codex = CodexDataReader.shared.fetchUsageData()
            let combined = Self.computeCombinedPoints(claude: claude, codex: codex)
            
            DispatchQueue.main.async {
                self?.claudeData = claude
                self?.codexData = codex
                self?.combinedDailyPoints = combined
                self?.lastRefreshed = Date()
                self?.isRefreshing = false
            }
        }
    }
    
    private func setupTimer() {
        timer?.invalidate()
        guard refreshIntervalSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }
    
    static func computeCombinedPoints(
        claude: ClaudeUsageData,
        codex: CodexUsageData,
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
                claudeSessions: claudeSessionsMap[date] ?? 0
            )
        }
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
    
    var menuBarTitle: String {
        let total = codexData.todayTokens + claudeData.todayTokens
        return "⚡️ \(Self.formatTokens(total))"
    }
}
