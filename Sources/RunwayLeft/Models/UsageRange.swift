import Foundation

// MARK: - Time Range

/// Time window for the Models tab. Data is bucketed per calendar day, so
/// "1D" means today's bucket rather than a rolling 24 hours.
enum UsageRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var title: String {
        switch self {
        case .day: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .sixMonths: return "Last 6 months"
        case .year: return "Last 12 months"
        case .all: return "All time"
        }
    }

    /// Number of calendar days in the window, including today. `nil` = unbounded.
    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        case .year: return 365
        case .all: return nil
        }
    }
}

enum UsageAgent: String {
    case claude = "Claude"
    case codex = "Codex"
    case litellm = "LiteLLM"
}

struct ModelUsageEntry: Identifiable, Equatable {
    var id: String { "\(agent.rawValue)-\(modelName)" }
    let modelName: String
    let agent: UsageAgent
    let tokens: Int64
}

// MARK: - Aggregator

/// Pure aggregation of per-model token usage over a time range. Uses the
/// per-day buckets for bounded ranges and the all-time tables for `.all`.
enum ModelUsageAggregator {
    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Inclusive `yyyy-MM-dd` bounds for a bounded range; nil for `.all`.
    static func dateBounds(
        for range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: String, end: String)? {
        guard let days = range.days else { return nil }
        let formatter = dayFormatter(calendar: calendar)
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return (formatter.string(from: startDate), formatter.string(from: now))
    }

    static func entries(
        claude: ClaudeUsageData,
        codex: CodexUsageData,
        litellm: LiteLLMUsageData = LiteLLMUsageData(),
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ModelUsageEntry] {
        var claudeTotals: [String: Int64] = [:]
        var codexTotals: [String: Int64] = [:]
        var litellmTotals: [String: Int64] = [:]

        if let bounds = dateBounds(for: range, now: now, calendar: calendar) {
            for day in claude.dailyModelTokens where day.date >= bounds.start && day.date <= bounds.end {
                for (model, tokens) in day.tokensByModel {
                    claudeTotals[model, default: 0] += tokens
                }
            }
            for item in codex.dailyModelTokens where item.date >= bounds.start && item.date <= bounds.end {
                codexTotals[item.modelName, default: 0] += item.tokens
            }
            for item in litellm.dailyModelTokens where item.date >= bounds.start && item.date <= bounds.end {
                litellmTotals[item.modelName, default: 0] += item.tokens
            }
        } else {
            for model in claude.modelUsage {
                claudeTotals[model.modelName, default: 0] += model.totalTokens
            }
            for model in codex.modelBreakdown {
                codexTotals[model.modelName, default: 0] += model.totalTokens
            }
            // LiteLLM only has the fetched window; "all time" means that window.
            for item in litellm.dailyModelTokens {
                litellmTotals[item.modelName, default: 0] += item.tokens
            }
        }

        var entries: [ModelUsageEntry] = []
        entries.append(contentsOf: claudeTotals.map { ModelUsageEntry(modelName: $0.key, agent: .claude, tokens: $0.value) })
        entries.append(contentsOf: codexTotals.map { ModelUsageEntry(modelName: $0.key, agent: .codex, tokens: $0.value) })
        entries.append(contentsOf: litellmTotals.map { ModelUsageEntry(modelName: $0.key, agent: .litellm, tokens: $0.value) })

        return entries
            .filter { $0.tokens > 0 }
            .sorted {
                if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
                return $0.id < $1.id
            }
    }

    /// Human-readable span such as "Aug 28 – Sep 3" or "All time".
    static func spanLabel(
        for range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let days = range.days else { return "All time" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        if days == 1 {
            return formatter.string(from: now)
        }
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: now))"
    }
}
