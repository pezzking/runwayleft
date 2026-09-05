import SwiftUI

struct CodexDetailView: View {
    @ObservedObject var manager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CodexStatusCard(
                codex: manager.codexData,
                status: manager.codexStatus,
                statusEnabled: manager.vendorStatusEnabled
            )

            ServiceStatusCard(
                status: manager.codexStatus,
                enabled: manager.vendorStatusEnabled,
                title: "OpenAI status",
                onRetry: { manager.refreshVendorStatus(force: true) }
            )

            HStack(spacing: 8) {
                DetailCard(
                    title: "Total tokens",
                    value: UsageManager.formatTokens(manager.codexData.totalTokens),
                    icon: "bolt.ring.closed",
                    accentGradient: MacTheme.codexGradient,
                    primaryColor: MacTheme.codexPrimary
                )

                DetailCard(
                    title: "Sessions",
                    value: "\(manager.codexData.totalSessions)",
                    icon: "square.stack.3d.up.fill",
                    accentGradient: LinearGradient(colors: [Color.teal, Color.cyan], startPoint: .leading, endPoint: .trailing),
                    primaryColor: .teal
                )

                DetailCard(
                    title: "Resets",
                    value: "\(manager.codexData.availableResetsCount)",
                    icon: "arrow.triangle.2.circlepath",
                    accentGradient: LinearGradient(colors: [Color.mint, Color.green], startPoint: .leading, endPoint: .trailing),
                    primaryColor: .mint
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title: "Codex models used", trailing: "\(manager.codexData.modelBreakdown.count)")

                if manager.codexData.modelBreakdown.isEmpty {
                    EmptyNote(text: "No model usage found in ~/.codex/state_5.sqlite yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(manager.codexData.modelBreakdown) { model in
                            GlassCard(cornerRadius: MacTheme.innerRadius, padding: 10) {
                                HStack {
                                    Text(model.modelName)
                                        .appFont(.body, weight: .bold)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("\(model.sessionCount) sessions")
                                        .appFont(.caption, weight: .medium)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)

                                    Text(UsageManager.formatTokens(model.totalTokens))
                                        .appFont(.body, weight: .bold)
                                        .monospacedDigit()
                                        .foregroundColor(MacTheme.codexPrimary)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title: "Daily breakdown")

                if manager.codexData.dailyUsage.isEmpty {
                    EmptyNote(text: "No daily usage recorded yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(manager.codexData.dailyUsage.prefix(10))) { item in
                            GlassCard(cornerRadius: MacTheme.innerRadius, padding: 10) {
                                HStack {
                                    Text(item.date)
                                        .appFont(.body, weight: .semibold)
                                        .monospacedDigit()
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("\(item.sessionCount) session\(item.sessionCount == 1 ? "" : "s")")
                                        .appFont(.caption, weight: .medium)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)

                                    Text(UsageManager.formatTokens(item.tokensUsed))
                                        .appFont(.body, weight: .bold)
                                        .monospacedDigit()
                                        .foregroundColor(MacTheme.codexPrimary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
