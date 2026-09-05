import SwiftUI

struct ModelBreakdownView: View {
    @ObservedObject var manager: UsageManager

    private func gradient(for agent: UsageAgent) -> LinearGradient {
        switch agent {
        case .claude: return MacTheme.claudeGradient
        case .codex: return MacTheme.codexGradient
        case .litellm: return MacTheme.litellmGradient
        }
    }

    private func color(for agent: UsageAgent) -> Color {
        switch agent {
        case .claude: return MacTheme.claudePrimary
        case .codex: return MacTheme.codexPrimary
        case .litellm: return MacTheme.litellmPrimary
        }
    }

    private var statColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: manager.liteLLMEnabled ? 2 : 3)
    }

    var body: some View {
        let entries = manager.modelEntries
        let rangeTotal = entries.map { $0.tokens }.reduce(0, +)
        let claudeTotal = entries.filter { $0.agent == .claude }.map { $0.tokens }.reduce(0, +)
        let codexTotal = entries.filter { $0.agent == .codex }.map { $0.tokens }.reduce(0, +)
        let litellmTotal = entries.filter { $0.agent == .litellm }.map { $0.tokens }.reduce(0, +)
        let share: (Int64) -> String = { part in
            rangeTotal > 0 ? String(format: "%.0f%% of total", Double(part) / Double(rangeTotal) * 100) : "—"
        }

        VStack(alignment: .leading, spacing: 12) {
            // Range selector
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $manager.modelsRange) {
                    ForEach(UsageRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                HStack(alignment: .firstTextBaseline) {
                    Text(manager.modelsRange.title)
                        .appFont(.body, weight: .semibold)
                        .foregroundColor(.primary)
                    Text("·")
                        .appFont(.caption)
                        .foregroundColor(.secondary)
                    Text(ModelUsageAggregator.spanLabel(for: manager.modelsRange))
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(entries.count) model\(entries.count == 1 ? "" : "s")")
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            // Range totals
            LazyVGrid(columns: statColumns, spacing: 8) {
                MiniStat(
                    label: "Total",
                    value: UsageManager.formatTokens(rangeTotal),
                    detail: "tokens",
                    icon: "sum",
                    color: MacTheme.accentBlue
                )
                MiniStat(
                    label: "Claude",
                    value: UsageManager.formatTokens(claudeTotal),
                    detail: share(claudeTotal),
                    icon: nil,
                    brandImage: BrandAssets.shared.claudeIcon14,
                    color: MacTheme.claudePrimary
                )
                MiniStat(
                    label: "Codex",
                    value: UsageManager.formatTokens(codexTotal),
                    detail: share(codexTotal),
                    icon: nil,
                    brandImage: BrandAssets.shared.codexIcon14,
                    color: MacTheme.codexPrimary
                )
                if manager.liteLLMEnabled {
                    MiniStat(
                        label: "LiteLLM",
                        value: UsageManager.formatTokens(litellmTotal),
                        detail: manager.modelsRange == .all ? "last \(max(manager.liteLLMData.windowDays, 1))d · \(share(litellmTotal))" : share(litellmTotal),
                        icon: "point.3.connected.trianglepath.dotted",
                        color: MacTheme.litellmPrimary
                    )
                }
            }

            Eyebrow(title: "By model")

            if entries.isEmpty {
                EmptyNote(text: manager.modelsRange == .all
                    ? "No model usage recorded yet. Use Claude Code or Codex and refresh."
                    : "No usage in this period. Try a longer range.")
            } else {
                let grandTotal = max(rangeTotal, 1)

                VStack(spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                        let percentage = Double(item.tokens) / Double(grandTotal) * 100.0

                        GlassCard(cornerRadius: MacTheme.innerRadius, padding: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    Text("#\(index + 1)")
                                        .appFont(.caption, weight: .bold)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                        .frame(width: 26, alignment: .leading)

                                    Text(item.modelName)
                                        .appFont(.headline, weight: .bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Pill(text: item.agent.rawValue, color: color(for: item.agent))

                                    Text(UsageManager.formatTokens(item.tokens))
                                        .appFont(.headline, weight: .bold)
                                        .monospacedDigit()
                                        .foregroundColor(color(for: item.agent))
                                }

                                ModernProgressBar(valuePct: percentage, accentGradient: gradient(for: item.agent), height: 6)

                                Text(String(format: "%.1f%% of %@", percentage, manager.modelsRange == .all ? "all-time usage" : "this period"))
                                    .appFont(.caption, weight: .medium)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
