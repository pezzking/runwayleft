import SwiftUI

struct DailyChartView: View {
    @ObservedObject var manager: UsageManager
    @Environment(\.textScale) private var scale
    @State private var hoveredPoint: CombinedDailyPoint? = nil

    private var spanLabel: String? {
        guard let first = manager.combinedDailyPoints.first, let last = manager.combinedDailyPoints.last else { return nil }
        return "\(first.formattedDate) – \(last.formattedDate)"
    }

    private var showsLiteLLM: Bool {
        manager.liteLLMEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(title: "Daily tokens · 14 days", trailing: spanLabel)

                HStack(spacing: 12) {
                    LegendItem(gradient: MacTheme.codexGradient, label: "Codex")
                    LegendItem(gradient: MacTheme.claudeGradient, label: "Claude")
                    if showsLiteLLM {
                        LegendItem(gradient: MacTheme.litellmGradient, label: "LiteLLM")
                    }
                }
                .padding(.leading, 10)
            }

            if manager.combinedDailyPoints.isEmpty {
                GlassCard {
                    Text("No activity recorded yet.")
                        .appFont(.body, weight: .medium)
                        .foregroundColor(.secondary)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                }
            } else {
                let maxTokens = max(manager.combinedDailyPoints.map { $0.totalTokens }.max() ?? 1, 1)
                let barAreaHeight: CGFloat = 96 * scale

                GlassCard(cornerRadius: MacTheme.cornerRadius, padding: 12) {
                    VStack(spacing: 10) {
                        ZStack {
                            if let hovered = hoveredPoint {
                                HStack(spacing: 10) {
                                    Text(hovered.formattedDate)
                                        .appFont(.body, weight: .bold)
                                        .monospacedDigit()
                                        .foregroundColor(.primary)

                                    Spacer()

                                    HoverValue(color: MacTheme.codexPrimary, label: "Codex", tokens: hovered.codexTokens)
                                    HoverValue(color: MacTheme.claudePrimary, label: "Claude", tokens: hovered.claudeTokens)
                                    if showsLiteLLM {
                                        HoverValue(color: MacTheme.litellmPrimary, label: "LiteLLM", tokens: hovered.liteLLMTokens)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.point.up.left.fill")
                                        .appFont(.caption)
                                    Text("Hover a bar to see that day's split")
                                        .appFont(.caption, weight: .medium)
                                    Spacer()
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                            }
                        }
                        .frame(height: 30 * scale)

                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(manager.combinedDailyPoints) { point in
                                let isHovered = hoveredPoint?.id == point.id

                                VStack(spacing: 5) {
                                    GeometryReader { geo in
                                        let availableHeight = geo.size.height
                                        let totalHeight = CGFloat(point.totalTokens) / CGFloat(maxTokens) * availableHeight
                                        let scaleFor: (Int64) -> CGFloat = { tokens in
                                            point.totalTokens > 0 ? totalHeight * CGFloat(tokens) / CGFloat(point.totalTokens) : 0
                                        }

                                        VStack(spacing: 1.5) {
                                            Spacer(minLength: 0)

                                            if point.liteLLMTokens > 0 {
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(MacTheme.litellmGradient)
                                                    .frame(height: max(scaleFor(point.liteLLMTokens), 4))
                                                    .shadow(color: MacTheme.litellmPrimary.opacity(isHovered ? 0.45 : 0.0), radius: 4)
                                            }

                                            if point.claudeTokens > 0 {
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(MacTheme.claudeGradient)
                                                    .frame(height: max(scaleFor(point.claudeTokens), 4))
                                                    .shadow(color: MacTheme.claudePrimary.opacity(isHovered ? 0.45 : 0.0), radius: 4)
                                            }

                                            if point.codexTokens > 0 {
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(MacTheme.codexGradient)
                                                    .frame(height: max(scaleFor(point.codexTokens), 4))
                                                    .shadow(color: MacTheme.codexPrimary.opacity(isHovered ? 0.45 : 0.0), radius: 4)
                                            }

                                            if point.totalTokens == 0 {
                                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                    .fill(Color.primary.opacity(0.08))
                                                    .frame(height: 3)
                                            }
                                        }
                                    }
                                    .frame(height: barAreaHeight)

                                    // Day-of-month only: full labels don't fit 14 columns.
                                    Text(point.dayOfMonth)
                                        .appFont(.micro, weight: isHovered ? .bold : .medium)
                                        .monospacedDigit()
                                        .foregroundColor(isHovered ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 2)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                                )
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if hovering {
                                            hoveredPoint = point
                                        } else if hoveredPoint?.id == point.id {
                                            hoveredPoint = nil
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
}

private struct HoverValue: View {
    let color: Color
    let label: String
    let tokens: Int64

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label) \(UsageManager.formatTokens(tokens))")
                .appFont(.body, weight: .bold)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let gradient: LinearGradient
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(gradient)
                .frame(width: 8, height: 8)
            Text(label)
                .appFont(.caption, weight: .semibold)
                .foregroundColor(.secondary)
        }
    }
}
