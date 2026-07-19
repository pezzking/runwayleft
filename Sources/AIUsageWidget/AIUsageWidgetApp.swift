import SwiftUI

@main
struct AIUsageWidgetApp: App {
    @StateObject private var manager = UsageManager.shared
    
    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu.fill")
                Text(manager.menuBarTitle)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .leading)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
