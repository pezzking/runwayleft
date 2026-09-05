import Foundation

struct CodexDailyUsage: Identifiable {
    var id: String { date }
    let date: String
    let sessionCount: Int
    let tokensUsed: Int64
}

struct CodexModelUsage: Identifiable {
    var id: String { modelName }
    let modelName: String
    let sessionCount: Int
    let totalTokens: Int64
}

/// One (day, model) bucket from the local Codex database.
struct CodexDailyModelTokens: Identifiable, Equatable {
    var id: String { "\(date)-\(modelName)" }
    let date: String
    let modelName: String
    let sessionCount: Int
    let tokens: Int64
}

struct CodexResetItem: Identifiable, Codable, Equatable {
    var id: String { "\(index)-\(expiryText)" }
    let index: Int
    let name: String
    let expiryText: String
}

struct CodexUsageData {
    var dailyUsage: [CodexDailyUsage] = []
    var dailyModelTokens: [CodexDailyModelTokens] = []
    var modelBreakdown: [CodexModelUsage] = []
    var totalSessions: Int = 0
    var totalTokens: Int64 = 0

    // Official /status Attributes
    var accountEmail: String = ""
    var accountPlan: String = ""
    var activeModel: String = ""

    // Rolling local activity window (not a subscription quota).
    var tokensIn1WeekWindow: Int64 = 0
    var sessionsIn1WeekWindow: Int = 0

    // Rate limits from the app-server (or the CLI's session logs as fallback).
    // Codex has a 5-hour window and a 7-day window.
    var sessionLimitUsedPct: Double?
    var sessionLimitResetText: String = ""
    var weeklyLimitUsedPct: Double?
    var weeklyLimitResetText: String = ""
    var resets: [CodexResetItem] = []
    var availableResetCreditsCount: Int?

    var availableResetsCount: Int { availableResetCreditsCount ?? resets.count }
    var hasResetsAvailable: Bool { availableResetsCount > 0 }
    var hasRateLimits: Bool { sessionLimitUsedPct != nil || weeklyLimitUsedPct != nil }

    var todayUsage: CodexDailyUsage? {
        let todayStr = DayFormat.today
        return dailyUsage.first { $0.date == todayStr }
    }

    var todayTokens: Int64 {
        todayUsage?.tokensUsed ?? 0
    }

    var todaySessions: Int {
        todayUsage?.sessionCount ?? 0
    }
}
