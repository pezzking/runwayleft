import SwiftUI

struct ClaudeDetailView: View {
    @ObservedObject var manager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClaudeStatusCard(
                claude: manager.claudeData,
                status: manager.claudeStatus,
                statusEnabled: manager.vendorStatusEnabled
            )

            ServiceStatusCard(
                status: manager.claudeStatus,
                enabled: manager.vendorStatusEnabled,
                title: "Anthropic status",
                onRetry: { manager.refreshVendorStatus(force: true) }
            )

            HStack(spacing: 10) {
                DetailCard(
                    title: "Total messages",
                    value: "\(manager.claudeData.totalMessages)",
                    icon: "bubble.left.and.bubble.right.fill",
                    accentGradient: MacTheme.claudeGradient,
                    primaryColor: MacTheme.claudePrimary
                )

                DetailCard(
                    title: "Total sessions",
                    value: "\(manager.claudeData.totalSessions)",
                    icon: "square.stack.3d.up.fill",
                    accentGradient: LinearGradient(colors: [Color.purple, Color.pink], startPoint: .leading, endPoint: .trailing),
                    primaryColor: .pink
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title: "Claude models", trailing: "\(manager.claudeData.modelUsage.count)")

                if manager.claudeData.modelUsage.isEmpty {
                    EmptyNote(text: "No model usage recorded in ~/.claude/stats-cache.json yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(manager.claudeData.modelUsage) { model in
                            ClaudeModelRow(model: model)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title: "Recent daily activity")

                if manager.claudeData.dailyActivity.isEmpty {
                    EmptyNote(text: "No daily activity recorded yet.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(manager.claudeData.dailyActivity.suffix(10).reversed())) { act in
                            GlassCard(cornerRadius: MacTheme.innerRadius, padding: 10) {
                                HStack {
                                    Text(act.date)
                                        .appFont(.body, weight: .semibold)
                                        .monospacedDigit()
                                        .foregroundColor(.primary)
                                    Spacer()

                                    HStack(spacing: 4) {
                                        Text("\(act.messageCount)")
                                            .appFont(.body, weight: .bold)
                                            .monospacedDigit()
                                            .foregroundColor(MacTheme.claudePrimary)
                                        Text("msgs")
                                            .appFont(.caption, weight: .medium)
                                            .foregroundColor(.secondary)
                                    }

                                    Text("·")
                                        .appFont(.caption)
                                        .foregroundColor(.secondary)

                                    HStack(spacing: 4) {
                                        Text("\(act.toolCallCount)")
                                            .appFont(.body, weight: .bold)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                        Text("tools")
                                            .appFont(.caption, weight: .medium)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        GlassCard(cornerRadius: MacTheme.innerRadius, padding: 12) {
            HStack {
                Text(text)
                    .appFont(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}
