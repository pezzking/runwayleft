import SwiftUI

@main
struct RunwayLeftApp: App {
    @StateObject private var manager = UsageManager.shared

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
        } label: {
            Image(nsImage: manager.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}
