import Foundation

// MARK: - Rows

struct LiteLLMDailyUsage: Identifiable, Equatable {
    var id: String { date }
    let date: String
    let spend: Double
    let promptTokens: Int64
    let completionTokens: Int64
    let totalTokens: Int64
    let requests: Int
}

struct LiteLLMDailyModelUsage: Identifiable, Equatable {
    var id: String { "\(date)-\(modelName)" }
    let date: String
    let modelName: String
    let spend: Double
    let tokens: Int64
    let requests: Int
}

// MARK: - Connection State

/// What the last exchange with the proxy told us. Drives the card pill and
/// the menu bar alert.
enum LiteLLMConnectionState: Equatable {
    case notConfigured
    case unknown
    case connected
    case unreachable(String)
    case unauthorized
    /// The proxy answers but has no database, so spend endpoints fail.
    case noSpendTracking
    case error(String)

    var label: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .unknown: return "Checking…"
        case .connected: return "Connected"
        case .unreachable: return "Unreachable"
        case .unauthorized: return "Key rejected"
        case .noSpendTracking: return "No spend tracking"
        case .error: return "Error"
        }
    }

    var detail: String? {
        switch self {
        case .unreachable(let message): return message
        case .error(let message): return message
        case .unauthorized: return "The proxy returned 401/403 for this key."
        case .noSpendTracking: return "This proxy has no database configured, so /key/info and /user/daily/activity are unavailable."
        default: return nil
        }
    }

    var level: StatusLevel {
        switch self {
        case .connected: return .operational
        case .unknown, .notConfigured: return .unknown
        case .noSpendTracking, .unauthorized: return .degraded
        case .unreachable, .error: return .majorOutage
        }
    }

    var isProblem: Bool { level.isProblem }
}

// MARK: - Usage Data

struct LiteLLMUsageData {
    var isConfigured: Bool = false
    var endpointHost: String = ""
    var keyAlias: String = ""

    // From /key/info (optional: a key can be created without a budget).
    var spend: Double? = nil
    var maxBudget: Double? = nil
    var budgetResetAt: Date? = nil
    var budgetDuration: String? = nil
    var tpmLimit: Int? = nil
    var rpmLimit: Int? = nil

    // From /user/daily/activity, oldest first.
    var daily: [LiteLLMDailyUsage] = []
    var dailyModelTokens: [LiteLLMDailyModelUsage] = []
    var windowDays: Int = 0

    var connection: LiteLLMConnectionState = .notConfigured
    var fetchedAt: Date? = nil

    var hasBudget: Bool {
        guard let maxBudget = maxBudget else { return false }
        return maxBudget > 0
    }

    /// Percentage of the key's budget already spent, when a budget exists.
    var budgetUsedPct: Double? {
        guard let maxBudget = maxBudget, maxBudget > 0 else { return nil }
        return max(0, min(100, (spend ?? 0) / maxBudget * 100))
    }

    var todayUsage: LiteLLMDailyUsage? {
        let today = DayFormat.today
        return daily.first { $0.date == today }
    }

    var todayTokens: Int64 { todayUsage?.totalTokens ?? 0 }
    var todayRequests: Int { todayUsage?.requests ?? 0 }
    var todaySpend: Double { todayUsage?.spend ?? 0 }

    var windowSpend: Double { daily.reduce(0) { $0 + $1.spend } }
    var windowTokens: Int64 { daily.reduce(0) { $0 + $1.totalTokens } }
    var windowRequests: Int { daily.reduce(0) { $0 + $1.requests } }

    static func formatSpend(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.2f", value) }
        if value == 0 { return "$0" }
        return String(format: "$%.3f", value)
    }
}
