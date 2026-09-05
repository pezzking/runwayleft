import SwiftUI
import AppKit

enum AppTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case claude = "Claude"
    case codex = "Codex"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .claude: return "brain.head.profile"
        case .codex: return "terminal.fill"
        case .models: return "cpu.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var brandImage: NSImage? {
        switch self {
        case .claude: return BrandAssets.shared.claudeIcon14
        case .codex: return BrandAssets.shared.codexIcon14
        default: return nil
        }
    }
}

struct HeaderView: View {
    @ObservedObject var manager: UsageManager
    @Binding var selectedTab: AppTab

    @Environment(\.textScale) private var scale
    @State private var rotationAngle: Double = 0
    @State private var isRefreshHovered = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                brandMark

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("RunwayLeft")
                            .appFont(.hero, weight: .bold, design: .rounded)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        PulsingLiveBadge()
                    }

                    Text(manager.liteLLMEnabled ? "Claude Code · OpenAI Codex · LiteLLM" : "Claude Code · OpenAI Codex")
                        .appFont(.caption, weight: .medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    refreshButton

                    RelativeTimeText(date: manager.lastRefreshed, prefix: "Updated ")
                        .appFont(.micro, weight: .medium)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Tab Navigation
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    GlassSegmentButton(
                        title: tab.rawValue,
                        icon: tab.iconName,
                        brandImage: tab.brandImage,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MacTheme.cardStroke, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onChange(of: manager.isRefreshing) { refreshing in
            if refreshing {
                startSpinning()
            }
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        if let icon = BrandAssets.shared.appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32 * scale, height: 32 * scale)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30 * scale, height: 30 * scale)

                Image(systemName: "bolt.fill")
                    .appFont(.title, weight: .bold)
                    .foregroundColor(.white)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: {
            manager.refreshData(force: true)
        }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .appFont(.caption, weight: .bold)
                    .rotationEffect(Angle(degrees: rotationAngle))

                Text(manager.isRefreshing ? "Updating…" : "Refresh")
                    .appFont(.caption, weight: .semibold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(isRefreshHovered ? .primary : .secondary)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(isRefreshHovered ? 0.12 : 0.06))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(manager.isRefreshing)
        .help("Re-read local usage and re-check provider status")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isRefreshHovered = hovering
            }
        }
    }

    private func startSpinning() {
        withAnimation(.linear(duration: 0.8)) {
            rotationAngle += 360
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if manager.isRefreshing {
                startSpinning()
            }
        }
    }
}
