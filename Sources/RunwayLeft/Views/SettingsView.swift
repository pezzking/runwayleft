import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: UsageManager

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(manager.effectivePopoverHeight) },
            set: { manager.setPopoverHeight(CGFloat($0), persist: true) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { manager.launchAtLogin },
            set: { manager.setLaunchAtLogin($0) }
        )
    }

    private var appVersion: String {
        // Outside the app bundle (swift run, xctest) Bundle.main is someone else's.
        guard Bundle.main.bundleIdentifier?.hasPrefix("dev.runwayleft") == true else { return "development build" }
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        default: return "development build"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .appFont(.title, weight: .bold)
                    .foregroundColor(MacTheme.accentBlue)

                Text("Settings")
                    .appFont(.hero, weight: .bold, design: .rounded)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 2)

            appearanceSection
            menuBarSection
            refreshSection
            providerStatusSection
            liteLLMSection
            sourcesSection
            aboutSection
        }
        .onAppear {
            manager.refreshLaunchAtLoginStatus()
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            SettingRow(title: "Text size", subtitle: "Scales every label. Popover width grows with it.") {
                Picker("", selection: $manager.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 8) {
                SettingRow(
                    title: "Popover height",
                    subtitle: manager.popoverHeightMode == .fit
                        ? "Sized to the current tab, up to what fits on your screen. Drag the grip at the bottom edge to set a custom height."
                        : "Fixed height. Drag the grip at the bottom edge or use the slider."
                ) {
                    Picker("", selection: $manager.popoverHeightMode) {
                        ForEach(PopoverHeightMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }

                HStack(spacing: 10) {
                    Slider(
                        value: heightBinding,
                        in: Double(UsageManager.minPopoverHeight)...Double(manager.maxPopoverHeight),
                        step: 10
                    )
                    .controlSize(.small)
                    .disabled(manager.popoverHeightMode == .fit)

                    // verbatim: avoids locale digit grouping ("1.313") on the readout.
                    Text(verbatim: "\(Int(manager.effectivePopoverHeight)) pt")
                        .appFont(.caption, weight: .bold)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 58, alignment: .trailing)

                    Button("Reset") {
                        manager.resetPopoverHeight()
                    }
                    .controlSize(.small)
                    .disabled(manager.popoverHeightMode == .fit)
                    .help("Return to fit-to-content sizing")
                }
            }
        }
    }

    // MARK: - Menu Bar

    private var menuBarSection: some View {
        SettingsSection(title: "Menu bar") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .appFont(.caption, weight: .medium)
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Image(nsImage: manager.menuBarImage)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MacTheme.cardStroke, lineWidth: 1)
                )
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)

                Picker("", selection: $manager.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text(manager.menuBarStyle.detail)
                    .appFont(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.3)

            SettingRow(title: "Claude metric", subtitle: "Which Claude limit the menu bar percentage reflects.") {
                Picker("", selection: $manager.claudeMenuMetric) {
                    ForEach(ClaudeMenuMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
                .disabled(!manager.menuBarStyle.showsQuotas)
            }

            Divider().opacity(0.3)

            SettingRow(title: "Codex metric", subtitle: "Which Codex limit the menu bar percentage reflects.") {
                Picker("", selection: $manager.codexMenuMetric) {
                    ForEach(CodexMenuMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
                .disabled(!manager.menuBarStyle.showsQuotas)
            }

            Divider().opacity(0.3)

            ToggleRow(title: "Show Claude quota", subtitle: nil, isOn: $manager.showClaudeInMenuBar)
                .disabled(!manager.menuBarStyle.showsQuotas)
            ToggleRow(title: "Show Codex quota", subtitle: nil, isOn: $manager.showCodexInMenuBar)
                .disabled(!manager.menuBarStyle.showsQuotas)
            if manager.liteLLMEnabled {
                ToggleRow(title: "Show LiteLLM budget", subtitle: "Only when the key has a budget.", isOn: $manager.showLiteLLMInMenuBar)
                    .disabled(!manager.menuBarStyle.showsQuotas)
            }
            ToggleRow(title: "Use brand icons", subtitle: "Off shows “C” and “X” text labels instead.", isOn: $manager.menuBarBrandIcons)
                .disabled(!manager.menuBarStyle.showsQuotas)
            ToggleRow(
                title: "Outage outline",
                subtitle: "Outlines a provider's metric in orange (degraded) or red (outage) when its status page reports a problem.",
                isOn: $manager.menuBarStatusAlerts
            )
            .disabled(!manager.vendorStatusEnabled)
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        SettingsSection(title: "Refresh") {
            SettingRow(title: "Auto-refresh interval", subtitle: "Re-reads local usage on this schedule. Live quota checks and status pages run at most every 5 minutes; the Refresh button forces them.") {
                Picker("", selection: $manager.refreshIntervalSeconds) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                    Text("30 minutes").tag(1800.0)
                    Text("Manual only").tag(0.0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    // MARK: - Provider Status

    private var providerStatusSection: some View {
        SettingsSection(title: "Provider status") {
            ToggleRow(
                title: "Check provider status pages",
                subtitle: "Polls status.claude.com and status.openai.com (public, read-only, at most every five minutes). Apart from a LiteLLM proxy you configure below, this is the app's only network access.",
                isOn: $manager.vendorStatusEnabled
            )

            if manager.vendorStatusEnabled {
                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 6) {
                    ProviderStatusLine(name: "Anthropic", status: manager.claudeStatus)
                    ProviderStatusLine(name: "OpenAI", status: manager.codexStatus)
                }

                HStack {
                    Spacer()
                    Button(action: { manager.refreshVendorStatus(force: true) }) {
                        HStack(spacing: 4) {
                            if manager.isCheckingStatus {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Check now")
                        }
                        .appFont(.caption, weight: .semibold)
                    }
                    .controlSize(.small)
                    .disabled(manager.isCheckingStatus)
                }
            }
        }
    }

    // MARK: - LiteLLM

    private var liteLLMSection: some View {
        SettingsSection(title: "LiteLLM") {
            ToggleRow(
                title: "Read metrics from a LiteLLM proxy",
                subtitle: "Spend, tokens, and requests for your virtual key, plus its budget when it has one. Uses /key/info and /user/daily/activity.",
                isOn: $manager.liteLLMEnabled
            )

            if manager.liteLLMEnabled {
                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Endpoint")
                            .appFont(.body, weight: .semibold)
                        TextField("http://localhost:4000", text: $manager.liteLLMEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .appFont(.body)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("API key")
                            .appFont(.body, weight: .semibold)
                        SecureField("sk-…", text: $manager.liteLLMAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .appFont(.body)
                        Text("Stored as an owner-only file in ~/Library/Application Support/RunwayLeft, never in preferences. Sent only to the endpoint above.")
                            .appFont(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button(action: { manager.testLiteLLMConnection() }) {
                            HStack(spacing: 5) {
                                if manager.isTestingLiteLLM {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "bolt.horizontal.circle")
                                }
                                Text("Test connection")
                            }
                            .appFont(.caption, weight: .semibold)
                        }
                        .controlSize(.small)
                        .disabled(manager.isTestingLiteLLM)

                        if let fetched = manager.liteLLMData.fetchedAt {
                            RelativeTimeText(date: fetched, prefix: "Last fetched ")
                                .appFont(.micro, weight: .medium)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    if let test = manager.liteLLMTest {
                        VStack(alignment: .leading, spacing: 4) {
                            ConnectionTestLine(title: "Reachable", stage: test.reachable)
                            if let stage = test.authenticated {
                                ConnectionTestLine(title: "Authenticated", stage: stage)
                            }
                            if let stage = test.spendTracking {
                                ConnectionTestLine(title: "Spend tracking", stage: stage)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MacTheme.subtleFill)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        SettingsSection(title: "Local data sources") {
            SourceRow(
                name: "Codex SQLite database",
                path: "~/.codex/state_5.sqlite",
                exists: sourceExists("~/.codex/state_5.sqlite")
            )
            Divider().opacity(0.3)
            SourceRow(
                name: "Claude stats cache",
                path: "~/.claude/stats-cache.json",
                exists: sourceExists("~/.claude/stats-cache.json")
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "Application") {
            ToggleRow(
                title: "Launch at login",
                subtitle: manager.launchAtLoginNote ?? "Start RunwayLeft automatically when you sign in.",
                isOn: launchAtLoginBinding
            )

            Divider().opacity(0.3)

            HStack(spacing: 10) {
                if let icon = BrandAssets.shared.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("RunwayLeft")
                        .appFont(.body, weight: .bold)
                    Text("Version \(appVersion) · Native SwiftUI")
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .appFont(.caption, weight: .bold)
                        Text("Quit")
                            .appFont(.caption, weight: .bold)
                    }
                    .foregroundColor(MacTheme.danger)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(MacTheme.danger.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(MacTheme.danger.opacity(0.3), lineWidth: 0.75)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sourceExists(_ path: String) -> Bool {
        FileManager.default.fileExists(
            atPath: NSString(string: path).expandingTildeInPath
        )
    }
}

// MARK: - Building Blocks

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GlassCard(cornerRadius: MacTheme.cornerRadius, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(title: title)
                content
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let control: Control

    init(title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

struct ConnectionTestLine: View {
    let title: String
    let stage: LiteLLMDataReader.ConnectionTest.Stage

    var body: some View {
        let (passed, message): (Bool, String) = {
            switch stage {
            case .passed(let m): return (true, m)
            case .failed(let m): return (false, m)
            }
        }()
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .appFont(.caption, weight: .semibold)
                .foregroundColor(passed ? MacTheme.success : MacTheme.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(.caption, weight: .semibold)
                Text(message)
                    .appFont(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One provider per row so names and headlines never wrap or truncate.
struct ProviderStatusLine: View {
    let name: String
    let status: VendorStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.effectiveLevel.color)
                .frame(width: 7, height: 7)
            Text(name)
                .appFont(.caption, weight: .semibold)
                .fixedSize()
            Text(status.headline)
                .appFont(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if let fetched = status.fetchedAt {
                RelativeTimeText(date: fetched)
                    .appFont(.micro, weight: .medium)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }
}
