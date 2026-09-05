import Foundation

// MARK: - Menu Bar Settings

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconOnly
    case tokensOnly
    case quotasOnly
    case tokensAndQuotas

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconOnly: return "Icon"
        case .tokensOnly: return "Tokens"
        case .quotasOnly: return "Quotas"
        case .tokensAndQuotas: return "Both"
        }
    }

    var detail: String {
        switch self {
        case .iconOnly: return "Just the bolt. Status alerts still show as a dot."
        case .tokensOnly: return "Bolt plus today's combined token total."
        case .quotasOnly: return "Per-provider quota percentages only."
        case .tokensAndQuotas: return "Today's tokens followed by each provider's quota."
        }
    }

    var showsTokens: Bool {
        self == .tokensOnly || self == .tokensAndQuotas
    }

    var showsQuotas: Bool {
        self == .quotasOnly || self == .tokensAndQuotas
    }
}

enum ClaudeMenuMetric: String, CaseIterable, Identifiable {
    case session
    case weekAll
    case weekModel
    case highest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "Current session"
        case .weekAll: return "Week (all models)"
        case .weekModel: return "Week (model-specific)"
        case .highest: return "Highest of the three"
        }
    }
}

enum CodexMenuMetric: String, CaseIterable, Identifiable {
    case session
    case weekly
    case highest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "Current session (5h)"
        case .weekly: return "Current week"
        case .highest: return "Highest of the two"
        }
    }
}

struct MenuBarOptions: Equatable {
    var style: MenuBarStyle = .tokensAndQuotas
    var claudeMetric: ClaudeMenuMetric = .session
    var codexMetric: CodexMenuMetric = .session
    var showClaude: Bool = true
    var showCodex: Bool = true
    var showLiteLLM: Bool = true
    var useBrandIcons: Bool = true
    var showStatusAlerts: Bool = true
}

// MARK: - Segments

struct MenuBarSegment: Equatable {
    enum Icon: Equatable {
        case app
        case claude
        case codex
        case litellm
        case none
    }

    let icon: Icon
    let text: String
    /// When set, a colored dot is drawn on the segment to flag a vendor problem.
    var alert: StatusLevel? = nil
}

// MARK: - Composer

/// Pure function from usage data + settings to the list of menu bar segments.
/// Kept free of AppKit so it can be unit-tested.
enum MenuBarComposer {
    static func segments(
        claude: ClaudeUsageData,
        codex: CodexUsageData,
        litellm: LiteLLMUsageData = LiteLLMUsageData(),
        claudeStatus: StatusLevel? = nil,
        codexStatus: StatusLevel? = nil,
        liteLLMStatus: StatusLevel? = nil,
        options: MenuBarOptions
    ) -> [MenuBarSegment] {
        var result: [MenuBarSegment] = []

        let claudeAlert: StatusLevel? = (options.showStatusAlerts && (claudeStatus?.isProblem ?? false)) ? claudeStatus : nil
        let codexAlert: StatusLevel? = (options.showStatusAlerts && (codexStatus?.isProblem ?? false)) ? codexStatus : nil
        let liteLLMAlert: StatusLevel? = (options.showStatusAlerts && (liteLLMStatus?.isProblem ?? false)) ? liteLLMStatus : nil
        let anyAlert: StatusLevel? = [claudeAlert, codexAlert, liteLLMAlert].compactMap { $0 }.max()

        // Leading app segment (icon-only / tokens).
        if options.style == .iconOnly {
            result.append(MenuBarSegment(icon: .app, text: "", alert: anyAlert))
            return result
        }

        if options.style.showsTokens {
            let total = codex.todayTokens + claude.todayTokens + litellm.todayTokens
            result.append(MenuBarSegment(icon: .app, text: UsageManager.formatTokens(total)))
        }

        var vendorSegments: [MenuBarSegment] = []

        if options.style.showsQuotas {
            if options.showClaude, let text = claudeText(claude, metric: options.claudeMetric) {
                vendorSegments.append(MenuBarSegment(
                    icon: options.useBrandIcons ? .claude : .none,
                    text: options.useBrandIcons ? text : "C \(text)",
                    alert: claudeAlert
                ))
            }

            if options.showCodex, let value = codexMetricValue(codex, metric: options.codexMetric) {
                let text = "\(Int(round(value)))%"
                vendorSegments.append(MenuBarSegment(
                    icon: options.useBrandIcons ? .codex : .none,
                    text: options.useBrandIcons ? text : "X \(text)",
                    alert: codexAlert
                ))
            }

            // LiteLLM shows its budget only; a key without a budget has no percentage to show.
            if options.showLiteLLM, litellm.isConfigured, let budget = litellm.budgetUsedPct {
                let text = "\(Int(round(budget)))%"
                vendorSegments.append(MenuBarSegment(
                    icon: options.useBrandIcons ? .litellm : .none,
                    text: options.useBrandIcons ? text : "L \(text)",
                    alert: liteLLMAlert
                ))
            }
        }

        result.append(contentsOf: vendorSegments)

        // If no vendor segment carried the alert, surface it on the first segment.
        if let alert = anyAlert, !result.contains(where: { $0.alert != nil }) {
            if result.isEmpty {
                result.append(MenuBarSegment(icon: .app, text: "", alert: alert))
            } else {
                var first = result[0]
                first.alert = alert
                result[0] = first
            }
        }

        // Quotas-only with nothing to show falls back to the bolt so the item stays clickable.
        if result.isEmpty {
            result.append(MenuBarSegment(icon: .app, text: "", alert: anyAlert))
        }

        return result
    }

    static func claudeMetricValue(_ claude: ClaudeUsageData, metric: ClaudeMenuMetric) -> Double? {
        guard claude.hasLiveStatus else { return nil }
        switch metric {
        case .session: return claude.sessionUsedPct
        case .weekAll: return claude.weekAllModelsPct
        case .weekModel: return claude.weekFablePct
        case .highest: return max(claude.sessionUsedPct, claude.weekAllModelsPct, claude.weekFablePct)
        }
    }

    /// Falls back to whichever window is available when the preferred one is missing.
    static func codexMetricValue(_ codex: CodexUsageData, metric: CodexMenuMetric) -> Double? {
        switch metric {
        case .session: return codex.sessionLimitUsedPct ?? codex.weeklyLimitUsedPct
        case .weekly: return codex.weeklyLimitUsedPct ?? codex.sessionLimitUsedPct
        case .highest:
            let values = [codex.sessionLimitUsedPct, codex.weeklyLimitUsedPct].compactMap { $0 }
            return values.max()
        }
    }

    private static func claudeText(_ claude: ClaudeUsageData, metric: ClaudeMenuMetric) -> String? {
        if let value = claudeMetricValue(claude, metric: metric) {
            return "\(Int(round(value)))%"
        }
        if claude.grandTotalTokens > 0 {
            return "Expired"
        }
        return nil
    }
}
