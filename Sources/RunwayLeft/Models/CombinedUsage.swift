import Foundation

struct CombinedDailyPoint: Identifiable {
    var id: String { date }
    let date: String
    let codexTokens: Int64
    let claudeTokens: Int64
    let codexSessions: Int
    let claudeSessions: Int
    let liteLLMTokens: Int64

    init(date: String, codexTokens: Int64, claudeTokens: Int64, codexSessions: Int, claudeSessions: Int, liteLLMTokens: Int64 = 0) {
        self.date = date
        self.codexTokens = codexTokens
        self.claudeTokens = claudeTokens
        self.codexSessions = codexSessions
        self.claudeSessions = claudeSessions
        self.liteLLMTokens = liteLLMTokens
    }

    var totalTokens: Int64 {
        codexTokens + claudeTokens + liteLLMTokens
    }
    
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var parsedDate: Date? {
        DayFormat.date(from: date)
    }

    var formattedDate: String {
        guard let d = parsedDate else { return date }
        return Self.monthDayFormatter.string(from: d)
    }

    /// Day-of-month only, for narrow chart axis labels.
    var dayOfMonth: String {
        guard let d = parsedDate else { return String(date.suffix(2)) }
        return Self.dayFormatter.string(from: d)
    }
}
