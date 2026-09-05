import SwiftUI

struct OverviewView: View {
    @ObservedObject var manager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TodaySummaryStrip(
                claude: manager.claudeData,
                codex: manager.codexData,
                litellm: manager.liteLLMEnabled ? manager.liteLLMData : nil
            )

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(title: "Subscription limits")

                ClaudeStatusCard(
                    claude: manager.claudeData,
                    status: manager.claudeStatus,
                    statusEnabled: manager.vendorStatusEnabled
                )

                CodexStatusCard(
                    codex: manager.codexData,
                    status: manager.codexStatus,
                    statusEnabled: manager.vendorStatusEnabled
                )

                if manager.liteLLMEnabled {
                    LiteLLMStatusCard(data: manager.liteLLMData, endpointURL: manager.liteLLMConfig?.endpoint)
                }
            }

            DailyChartView(manager: manager)

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(title: "Provider status")

                ServiceStatusCard(
                    status: manager.claudeStatus,
                    enabled: manager.vendorStatusEnabled,
                    title: "Anthropic status",
                    compact: true,
                    onRetry: { manager.refreshVendorStatus(force: true) }
                )

                ServiceStatusCard(
                    status: manager.codexStatus,
                    enabled: manager.vendorStatusEnabled,
                    title: "OpenAI status",
                    compact: true,
                    onRetry: { manager.refreshVendorStatus(force: true) }
                )
            }
        }
    }
}

// MARK: - Today Strip

/// Compact row of today's totals, matching what the menu bar shows. Wraps to a
/// second row when a fourth provider is enabled at the narrow text size.
struct TodaySummaryStrip: View {
    let claude: ClaudeUsageData
    let codex: CodexUsageData
    let litellm: LiteLLMUsageData?

    /// Three providers sit in one row; a fourth makes a balanced 2×2 grid.
    private var columns: [GridItem] {
        let count = litellm == nil ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        let total = claude.todayTokens + codex.todayTokens + (litellm?.todayTokens ?? 0)

        LazyVGrid(columns: columns, spacing: 8) {
            MiniStat(
                label: "Today",
                value: UsageManager.formatTokens(total),
                detail: "tokens",
                icon: "bolt.fill",
                color: MacTheme.accentBlue
            )

            MiniStat(
                label: "Claude",
                value: UsageManager.formatTokens(claude.todayTokens),
                detail: "\(claude.todayMessages) msgs",
                icon: nil,
                brandImage: BrandAssets.shared.claudeIcon14,
                color: MacTheme.claudePrimary
            )

            MiniStat(
                label: "Codex",
                value: UsageManager.formatTokens(codex.todayTokens),
                detail: "\(codex.todaySessions) session\(codex.todaySessions == 1 ? "" : "s")",
                icon: nil,
                brandImage: BrandAssets.shared.codexIcon14,
                color: MacTheme.codexPrimary
            )

            if let litellm = litellm {
                MiniStat(
                    label: "LiteLLM",
                    value: UsageManager.formatTokens(litellm.todayTokens),
                    detail: "\(litellm.todayRequests) req · \(LiteLLMUsageData.formatSpend(litellm.todaySpend))",
                    icon: "point.3.connected.trianglepath.dotted",
                    color: MacTheme.litellmPrimary
                )
            }
        }
    }
}

struct MiniStat: View {
    let label: String
    let value: String
    let detail: String
    let icon: String?
    var brandImage: NSImage? = nil
    let color: Color

    @Environment(\.textScale) private var scale

    var body: some View {
        GlassCard(cornerRadius: MacTheme.innerRadius, padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if let brandImage = brandImage {
                        Image(nsImage: brandImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12 * scale, height: 12 * scale)
                            .foregroundColor(color)
                    } else if let icon = icon {
                        Image(systemName: icon)
                            .appFont(.caption, weight: .bold)
                            .foregroundColor(color)
                    }
                    Text(label)
                        .appFont(.caption, weight: .semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(value)
                    .appFont(.title, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail)
                    .appFont(.micro, weight: .medium)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
