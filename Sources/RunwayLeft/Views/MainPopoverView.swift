import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var manager: UsageManager

    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var gripHeight: CGFloat = 0

    init(manager: UsageManager = .shared) {
        self._manager = ObservedObject(wrappedValue: manager)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(manager: manager, selectedTab: $manager.selectedTab)
                .readHeight { headerHeight = $0; reportFit() }

            Divider()
                .opacity(0.35)

            ScrollView(.vertical, showsIndicators: true) {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .readHeight { contentHeight = $0; reportFit() }
            }
            .frame(maxHeight: .infinity)

            ResizeGrip(manager: manager)
                .readHeight { gripHeight = $0; reportFit() }
        }
        .frame(width: manager.textSize.popoverWidth, height: manager.effectivePopoverHeight)
        .environment(\.textScale, manager.textSize.scale)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch manager.selectedTab {
        case .overview:
            OverviewView(manager: manager)
        case .claude:
            ClaudeDetailView(manager: manager)
        case .codex:
            CodexDetailView(manager: manager)
        case .models:
            ModelBreakdownView(manager: manager)
        case .settings:
            SettingsView(manager: manager)
        }
    }

    /// Content height depends only on the popover width, never on its height,
    /// so feeding it back into the frame cannot oscillate.
    private func reportFit() {
        guard headerHeight > 0, contentHeight > 0 else { return }
        let dividerHeight: CGFloat = 1
        manager.reportFitHeight(headerHeight + dividerHeight + contentHeight + gripHeight)
    }
}
