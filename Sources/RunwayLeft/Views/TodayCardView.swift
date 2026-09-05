import SwiftUI

// MARK: - Provider Card Header

struct VendorCardHeader: View {
    let brandImage: NSImage?
    let fallbackSymbol: String
    let gradient: LinearGradient
    let title: String
    let subtitle: String?
    let plan: String?
    let planColor: Color
    let status: VendorStatus
    let statusEnabled: Bool

    @Environment(\.textScale) private var scale

    var body: some View {
        let iconSize = 22 * scale

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let img = brandImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: fallbackSymbol)
                            .appFont(.title, weight: .semibold)
                            .foregroundStyle(gradient)
                    }
                }
                .frame(width: iconSize, height: iconSize)

                HStack(spacing: 7) {
                    Text(title)
                        .appFont(.title, weight: .bold, design: .rounded)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let plan = plan, !plan.isEmpty {
                        Pill(text: plan, color: planColor)
                    }
                }

                Spacer(minLength: 6)

                StatusPill(status: status, enabled: statusEnabled)
            }

            // Subtitle gets the full card width so emails and model names are not squeezed by the pill.
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .appFont(.caption, weight: .medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, iconSize + 10)
            }
        }
    }
}

// MARK: - Claude Status Card

struct ClaudeStatusCard: View {
    let claude: ClaudeUsageData
    let status: VendorStatus
    let statusEnabled: Bool

    var body: some View {
        let sessionPct = claude.sessionUsedPct
        let weekAllPct = claude.weekAllModelsPct
        let weekFablePct = claude.weekFablePct

        GlowingBrandCard(
            brandGradient: MacTheme.claudeGradient,
            borderColor: MacTheme.claudePrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VendorCardHeader(
                    brandImage: BrandAssets.shared.claudeIcon20,
                    fallbackSymbol: "brain.head.profile",
                    gradient: MacTheme.claudeGradient,
                    title: "Claude",
                    subtitle: "Claude Code CLI",
                    plan: nil,
                    planColor: MacTheme.claudePrimary,
                    status: status,
                    statusEnabled: statusEnabled
                )

                Divider().opacity(0.25)

                if claude.hasLiveStatus {
                    ProgressBarRow(
                        label: "Current session",
                        valueText: String(format: "%.0f%% used", sessionPct),
                        progressPct: sessionPct,
                        resetText: claude.sessionReset.isEmpty ? nil : "Resets \(claude.sessionReset)",
                        accentGradient: progressGradient(usedPct: sessionPct)
                    )

                    Divider().opacity(0.25)

                    ProgressBarRow(
                        label: "Current week · all models",
                        valueText: String(format: "%.0f%% used", weekAllPct),
                        progressPct: weekAllPct,
                        resetText: claude.weekAllModelsReset.isEmpty ? nil : "Resets \(claude.weekAllModelsReset)",
                        accentGradient: progressGradient(usedPct: weekAllPct)
                    )

                    Divider().opacity(0.25)

                    ProgressBarRow(
                        label: "Current week · \(claude.weekModelLabel)",
                        valueText: String(format: "%.0f%% used", weekFablePct),
                        progressPct: weekFablePct,
                        resetText: claude.weekFableReset.isEmpty ? nil : "Resets \(claude.weekFableReset)",
                        accentGradient: progressGradient(usedPct: weekFablePct)
                    )
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .appFont(.headline, weight: .semibold)
                            .foregroundColor(MacTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local session expired")
                                .appFont(.body, weight: .semibold)
                            Text("Run `claude` in a terminal and sign in again to see live session and weekly limits.")
                                .appFont(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Codex Status Card

struct CodexStatusCard: View {
    let codex: CodexUsageData
    let status: VendorStatus
    let statusEnabled: Bool

    private var subtitle: String? {
        let parts = [codex.activeModel, codex.accountEmail].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        GlowingBrandCard(
            brandGradient: MacTheme.codexGradient,
            borderColor: MacTheme.codexPrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VendorCardHeader(
                    brandImage: BrandAssets.shared.codexIcon20,
                    fallbackSymbol: "terminal.fill",
                    gradient: MacTheme.codexGradient,
                    title: "OpenAI Codex",
                    subtitle: subtitle,
                    plan: codex.accountPlan.isEmpty ? "Local" : codex.accountPlan,
                    planColor: MacTheme.codexPrimary,
                    status: status,
                    statusEnabled: statusEnabled
                )

                Divider().opacity(0.25)

                if codex.hasRateLimits {
                    if let sessionPct = codex.sessionLimitUsedPct {
                        ProgressBarRow(
                            label: "Current session · 5 hours",
                            valueText: String(format: "%.0f%% used", sessionPct),
                            progressPct: sessionPct,
                            resetText: codex.sessionLimitResetText.isEmpty ? nil : capitalizedFirst(codex.sessionLimitResetText),
                            accentGradient: progressGradient(usedPct: sessionPct)
                        )
                    }

                    if codex.sessionLimitUsedPct != nil && codex.weeklyLimitUsedPct != nil {
                        Divider().opacity(0.25)
                    }

                    if let weeklyPct = codex.weeklyLimitUsedPct {
                        ProgressBarRow(
                            label: "Current week",
                            valueText: String(format: "%.0f%% used", weeklyPct),
                            progressPct: weeklyPct,
                            resetText: codex.weeklyLimitResetText.isEmpty ? nil : capitalizedFirst(codex.weeklyLimitResetText),
                            accentGradient: progressGradient(usedPct: weeklyPct)
                        )
                    }
                } else {
                    HStack {
                        Text("Rate limits")
                            .appFont(.body, weight: .semibold)
                        Spacer()
                        Text("No snapshot recorded")
                            .appFont(.caption, weight: .medium)
                            .foregroundColor(.secondary)
                    }
                }

                Divider().opacity(0.25)

                // Reset credits
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("Limit resets available", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            .appFont(.body, weight: .semibold)
                            .foregroundColor(MacTheme.codexPrimary)

                        Spacer()

                        Text(
                            codex.availableResetCreditsCount != nil
                                ? (codex.hasResetsAvailable ? "\(codex.availableResetsCount) available" : "None available")
                                : "Unavailable"
                        )
                        .appFont(.caption, weight: .bold)
                        .monospacedDigit()
                        .foregroundColor(codex.hasResetsAvailable ? MacTheme.codexPrimary : .secondary)
                    }

                    ForEach(codex.resets) { item in
                        ResetCreditRow(index: item.index, name: item.name, detail: "Expires \(item.expiryText)")
                    }

                    let missingResetDetails = max(0, codex.availableResetsCount - codex.resets.count)
                    if missingResetDetails > 0 {
                        ForEach(0..<missingResetDetails, id: \.self) { offset in
                            ResetCreditRow(
                                index: codex.resets.count + offset + 1,
                                name: "Reset credit",
                                detail: "Expiry not provided"
                            )
                        }
                    }
                }
            }
        }
    }
}

struct ResetCreditRow: View {
    let index: Int
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index).")
                .appFont(.caption, weight: .bold)
                .monospacedDigit()
                .foregroundColor(MacTheme.codexPrimary)
            Text(name)
                .appFont(.caption, weight: .medium)
            Spacer()
            Text(detail)
                .appFont(.caption, weight: .medium)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(MacTheme.subtleFill)
        )
    }
}

// MARK: - Progress Bar Row

struct ProgressBarRow: View {
    let label: String
    let valueText: String
    let progressPct: Double
    let resetText: String?
    let accentGradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(valueText)
                    .appFont(.body, weight: .bold)
                    .monospacedDigit()
                    .foregroundColor(progressTextColor(usedPct: progressPct))
                    .lineLimit(1)
            }

            ModernProgressBar(valuePct: progressPct, accentGradient: accentGradient, height: 7)

            if let reset = resetText, !reset.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .appFont(.micro, weight: .medium)
                    Text(reset)
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Helpers

/// "resets Sep 4 at 1:38 AM" → "Resets Sep 4 at 1:38 AM", so both providers read the same.
func capitalizedFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}

func progressGradient(usedPct: Double) -> LinearGradient {
    if usedPct >= 85.0 {
        return LinearGradient(colors: [MacTheme.danger, Color.red], startPoint: .leading, endPoint: .trailing)
    } else if usedPct >= 60.0 {
        return LinearGradient(colors: [MacTheme.warning, Color.orange], startPoint: .leading, endPoint: .trailing)
    } else {
        return LinearGradient(colors: [MacTheme.success, MacTheme.codexPrimary], startPoint: .leading, endPoint: .trailing)
    }
}

func progressTextColor(usedPct: Double) -> Color {
    if usedPct >= 85.0 {
        return MacTheme.danger
    } else if usedPct >= 60.0 {
        return MacTheme.warning
    } else {
        return MacTheme.success
    }
}
