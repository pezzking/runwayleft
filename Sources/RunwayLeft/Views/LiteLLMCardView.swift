import SwiftUI
import AppKit

// MARK: - Connection Pill

struct LiteLLMConnectionPill: View {
    let state: LiteLLMConnectionState
    let endpointURL: URL?

    @State private var isHovered = false

    private var color: Color {
        state.level == .unknown ? .secondary : state.level.color
    }

    var body: some View {
        Button(action: {
            if let url = endpointURL {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(state.isProblem ? 0.6 : 0.0), radius: 3)
                Text(state.label)
                    .appFont(.micro, weight: .bold)
                    .lineLimit(1)
                if endpointURL != nil {
                    Image(systemName: "arrow.up.right")
                        .appFont(.micro, weight: .bold)
                        .opacity(isHovered ? 1 : 0.5)
                }
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(color.opacity(isHovered ? 0.22 : 0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(state.detail ?? (endpointURL.map { "Open \($0.absoluteString)" } ?? state.label))
    }
}

// MARK: - Card

struct LiteLLMStatusCard: View {
    let data: LiteLLMUsageData
    let endpointURL: URL?

    @Environment(\.textScale) private var scale

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        GlowingBrandCard(
            brandGradient: MacTheme.litellmGradient,
            borderColor: MacTheme.litellmPrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                header

                Divider().opacity(0.25)

                if let detail = data.connection.detail, data.connection.isProblem || data.connection == .noSpendTracking {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .appFont(.headline, weight: .semibold)
                            .foregroundColor(data.connection.level.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.connection.label)
                                .appFont(.body, weight: .semibold)
                            Text(detail)
                                .appFont(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if data.hasBudget, let pct = data.budgetUsedPct {
                    ProgressBarRow(
                        label: "Budget · \(LiteLLMUsageData.formatSpend(data.spend ?? 0)) of \(LiteLLMUsageData.formatSpend(data.maxBudget ?? 0))",
                        valueText: String(format: "%.0f%% used", pct),
                        progressPct: pct,
                        resetText: resetText,
                        accentGradient: progressGradient(usedPct: pct)
                    )
                } else if data.connection == .connected {
                    HStack {
                        Text("Budget")
                            .appFont(.body, weight: .semibold)
                        Spacer()
                        Text(data.keyAlias.isEmpty ? "No budget on this key" : "No budget on “\(data.keyAlias)”")
                            .appFont(.caption, weight: .medium)
                            .foregroundColor(.secondary)
                    }
                }

                if data.connection == .connected {
                    Divider().opacity(0.25)

                    HStack(spacing: 8) {
                        LiteLLMStat(label: "Today", value: LiteLLMUsageData.formatSpend(data.todaySpend), detail: "\(UsageManager.formatTokens(data.todayTokens)) tokens")
                        LiteLLMStat(label: "Requests today", value: "\(data.todayRequests)", detail: "\(data.windowRequests) in \(data.windowDays)d")
                        LiteLLMStat(label: "Last \(data.windowDays) days", value: LiteLLMUsageData.formatSpend(data.windowSpend), detail: "\(UsageManager.formatTokens(data.windowTokens)) tokens")
                    }

                    if data.tpmLimit != nil || data.rpmLimit != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .appFont(.micro, weight: .medium)
                            Text(limitsText)
                                .appFont(.caption, weight: .medium)
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(MacTheme.litellmGradient)
                    .frame(width: 22 * scale, height: 22 * scale)

                HStack(spacing: 7) {
                    Text("LiteLLM")
                        .appFont(.title, weight: .bold, design: .rounded)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if !data.keyAlias.isEmpty {
                        Pill(text: data.keyAlias, color: MacTheme.litellmPrimary)
                    }
                }

                Spacer(minLength: 6)

                LiteLLMConnectionPill(state: data.connection, endpointURL: endpointURL)
            }

            if !data.endpointHost.isEmpty {
                Text(data.endpointHost)
                    .appFont(.caption, weight: .medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 22 * scale + 10)
            }
        }
    }

    private var resetText: String? {
        if let reset = data.budgetResetAt {
            return "Resets \(Self.resetFormatter.string(from: reset))"
        }
        if let duration = data.budgetDuration, !duration.isEmpty {
            return "Budget window: \(duration)"
        }
        return nil
    }

    private var limitsText: String {
        var parts: [String] = []
        if let tpm = data.tpmLimit { parts.append("\(UsageManager.formatTokens(Int64(tpm))) tokens/min") }
        if let rpm = data.rpmLimit { parts.append("\(rpm) req/min") }
        return "Limits: " + parts.joined(separator: " · ")
    }
}

struct LiteLLMStat: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .appFont(.micro, weight: .semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .appFont(.headline, weight: .bold, design: .rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .appFont(.micro, weight: .medium)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(MacTheme.subtleFill)
        )
    }
}
