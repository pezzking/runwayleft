import SwiftUI
import AppKit

// MARK: - Status Colors

extension StatusLevel {
    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .operational: return MacTheme.success
        case .maintenance: return MacTheme.info
        case .degraded: return MacTheme.warning
        case .partialOutage: return Color.orange
        case .majorOutage: return MacTheme.danger
        }
    }
}

// MARK: - Stat Card

struct DetailCard: View {
    let title: String
    let value: String
    let icon: String
    let accentGradient: LinearGradient
    let primaryColor: Color

    @Environment(\.textScale) private var scale

    var body: some View {
        GlassCard(cornerRadius: MacTheme.innerRadius, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(accentGradient.opacity(0.18))
                            .frame(width: 24 * scale, height: 24 * scale)

                        Image(systemName: icon)
                            .appFont(.caption, weight: .bold)
                            .foregroundColor(primaryColor)
                    }

                    Text(title)
                        .appFont(.caption, weight: .medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(value)
                    .appFont(.title, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Claude Model Row

struct ClaudeModelRow: View {
    let model: ClaudeModelDetail

    var body: some View {
        GlassCard(cornerRadius: MacTheme.innerRadius, padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(model.modelName)
                        .appFont(.body, weight: .bold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(UsageManager.formatTokens(model.totalTokens))
                        .appFont(.body, weight: .bold)
                        .monospacedDigit()
                        .foregroundColor(MacTheme.claudePrimary)
                }

                HStack(spacing: 6) {
                    LabelBadge(label: "In", val: UsageManager.formatTokens(model.inputTokens))
                    LabelBadge(label: "Out", val: UsageManager.formatTokens(model.outputTokens))
                    LabelBadge(label: "Cache read", val: UsageManager.formatTokens(model.cacheReadInputTokens))
                }
            }
        }
    }
}

struct LabelBadge: View {
    let label: String
    let val: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .appFont(.caption, weight: .medium)
                .foregroundColor(.secondary)
            Text(val)
                .appFont(.caption, weight: .bold)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(MacTheme.subtleFill)
        )
    }
}

// MARK: - Data Source Row

struct SourceRow: View {
    let name: String
    let path: String
    let exists: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                Text(path)
                    .appFont(.caption, weight: .regular, design: .monospaced)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Pill(
                text: exists ? "Connected" : "Missing",
                color: exists ? MacTheme.success : MacTheme.warning,
                icon: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
        }
    }
}

// MARK: - Vendor Status Pill

/// Compact status indicator for a vendor card header. Clicking opens the status page.
struct StatusPill: View {
    let status: VendorStatus
    let enabled: Bool

    @State private var isHovered = false

    private var level: StatusLevel {
        enabled ? status.effectiveLevel : .unknown
    }

    private var text: String {
        guard enabled else { return "Status off" }
        return status.headline
    }

    private var tooltip: String {
        guard enabled else { return "Provider status checks are turned off in Settings." }
        if let error = status.errorMessage {
            return "Could not reach \(status.vendor.pageHost): \(error)"
        }
        if status.isLoaded {
            let checked = status.fetchedAt.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? ""
            return "\(status.description). Checked \(checked). Click to open \(status.vendor.pageHost)."
        }
        return "Checking \(status.vendor.pageHost)…"
    }

    var body: some View {
        Button(action: {
            NSWorkspace.shared.open(status.pageURL)
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(level.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: level.color.opacity(level.isProblem ? 0.6 : 0.0), radius: 3)

                Text(text)
                    .appFont(.micro, weight: .bold)
                    .lineLimit(1)

                Image(systemName: "arrow.up.right")
                    .appFont(.micro, weight: .bold)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .foregroundColor(level == .unknown ? .secondary : level.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill((level == .unknown ? Color.secondary : level.color).opacity(isHovered ? 0.22 : 0.14)))
            .overlay(Capsule().strokeBorder((level == .unknown ? Color.secondary : level.color).opacity(0.35), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Service Status Card

/// Full status breakdown for a vendor: relevant components, anything else that
/// is degraded, open incidents, and scheduled maintenance.
struct ServiceStatusCard: View {
    let status: VendorStatus
    let enabled: Bool
    var title: String = "Service status"
    /// Compact cards (Overview) collapse healthy components into one line and
    /// only expand when something is degraded.
    var compact: Bool = false
    var onRetry: (() -> Void)? = nil

    var body: some View {
        GlassCard(cornerRadius: MacTheme.cornerRadius, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if !enabled {
                    Text("Provider status checks are turned off. Enable them in Settings to see live service health from \(status.vendor.pageHost).")
                        .appFont(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = status.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .appFont(.headline, weight: .semibold)
                            .foregroundColor(MacTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Couldn't reach \(status.vendor.pageHost)")
                                .appFont(.body, weight: .semibold)
                            Text(error)
                                .appFont(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if let onRetry = onRetry {
                            Button("Retry", action: onRetry)
                                .appFont(.caption, weight: .semibold)
                        }
                    }
                } else if !status.isLoaded {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking \(status.vendor.pageHost)…")
                            .appFont(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    loadedBody
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.title, weight: .bold, design: .rounded)
                .foregroundColor(.primary)

            Spacer()

            if enabled, status.isLoaded, let fetched = status.fetchedAt {
                RelativeTimeText(date: fetched, prefix: "Checked ")
                    .appFont(.micro, weight: .medium)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var loadedBody: some View {
        // Overall line
        HStack(spacing: 8) {
            Circle()
                .fill(status.indicator.level.color)
                .frame(width: 9, height: 9)
            Text(status.description.isEmpty ? status.indicator.level.label : status.description)
                .appFont(.body, weight: .semibold)
                .foregroundColor(.primary)
            Spacer()
            Button(action: { NSWorkspace.shared.open(status.pageURL) }) {
                HStack(spacing: 3) {
                    Text(status.vendor.pageHost)
                    Image(systemName: "arrow.up.right")
                }
                .appFont(.micro, weight: .semibold)
                // Same link color everywhere; brand colors are reserved for cards and pills.
                .foregroundColor(MacTheme.accentBlue)
            }
            .buttonStyle(.plain)
            .help("Open \(status.pageURL.absoluteString)")
        }

        let relevant = status.relevantComponents
        let affectedRelevant = relevant.filter { $0.status.level != .operational }

        if compact {
            if !affectedRelevant.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(title: "Affected components you use")
                    VStack(spacing: 4) {
                        ForEach(affectedRelevant) { component in
                            ComponentRow(component: component)
                        }
                    }
                }
            } else if !relevant.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundColor(MacTheme.success)
                    Text("Operational: " + relevant.map { $0.name }.joined(separator: " · "))
                        .appFont(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !relevant.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title: "Components you use")
                VStack(spacing: 4) {
                    ForEach(relevant) { component in
                        ComponentRow(component: component)
                    }
                }
            }
        }

        let others = status.otherAffectedComponents
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title: "Other affected services")
                VStack(spacing: 4) {
                    ForEach(others) { component in
                        ComponentRow(component: component)
                    }
                }
            }
        }

        let incidents = status.activeIncidents
        if !incidents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title: "Open incidents", trailing: "\(incidents.count)")
                VStack(spacing: 6) {
                    ForEach(incidents) { incident in
                        IncidentRow(incident: incident)
                    }
                }
            }
        }

        if !status.maintenances.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title: "Scheduled maintenance")
                VStack(spacing: 6) {
                    ForEach(status.maintenances) { item in
                        MaintenanceRow(maintenance: item)
                    }
                }
            }
        }

        if relevant.isEmpty && others.isEmpty && incidents.isEmpty && status.maintenances.isEmpty {
            Text("No components reported for this page.")
                .appFont(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ComponentRow: View {
    let component: StatusComponent

    var body: some View {
        let level = component.status.level
        HStack(spacing: 8) {
            Circle()
                .fill(level.color)
                .frame(width: 7, height: 7)
            Text(component.name)
                .appFont(.body, weight: .medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            Text(level.label)
                .appFont(.caption, weight: .semibold)
                .foregroundColor(level == .operational ? .secondary : level.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(level.isProblem ? level.color.opacity(0.10) : MacTheme.subtleFill)
        )
    }
}

struct IncidentRow: View {
    let incident: StatusIncident

    var body: some View {
        let level = incident.impactLevel
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(incident.name)
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Pill(text: (incident.impact ?? "unknown").capitalized, color: level == .unknown ? .secondary : level.color)
            }

            if let update = incident.latestUpdate, let body = update.body, !body.isEmpty {
                Text(body)
                    .appFont(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let state = incident.status, !state.isEmpty {
                    Text(state.capitalized)
                        .appFont(.micro, weight: .semibold)
                        .foregroundColor(.secondary)
                }
                if let when = VendorStatusService.formatTimestamp(incident.updatedAt ?? incident.createdAt) {
                    Text("· \(when)")
                        .appFont(.micro, weight: .medium)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let link = incident.link {
                    Button(action: { NSWorkspace.shared.open(link) }) {
                        HStack(spacing: 3) {
                            Text("Details")
                            Image(systemName: "arrow.up.right")
                        }
                        .appFont(.micro, weight: .semibold)
                        .foregroundColor(MacTheme.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(level.isProblem ? level.color.opacity(0.08) : MacTheme.subtleFill)
        )
    }
}

struct MaintenanceRow: View {
    let maintenance: StatusMaintenance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(maintenance.name)
                    .appFont(.body, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Pill(text: (maintenance.status ?? "scheduled").capitalized, color: MacTheme.info)
            }
            HStack(spacing: 6) {
                if let start = VendorStatusService.formatTimestamp(maintenance.scheduledFor) {
                    Text("Starts \(start)")
                }
                if let end = VendorStatusService.formatTimestamp(maintenance.scheduledUntil) {
                    Text("· until \(end)")
                }
                Spacer()
                if let link = maintenance.link {
                    Button(action: { NSWorkspace.shared.open(link) }) {
                        HStack(spacing: 3) {
                            Text("Details")
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundColor(MacTheme.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .appFont(.micro, weight: .medium)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacTheme.info.opacity(0.08))
        )
    }
}
