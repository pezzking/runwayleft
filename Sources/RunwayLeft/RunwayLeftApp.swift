import MenuBarExtraAccess
import SwiftUI

@main
struct RunwayLeftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = UsageManager.shared

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
        } label: {
            Image(nsImage: manager.menuBarImage)
        }
        // Must precede `.menuBarExtraStyle`: the modifier is defined on `MenuBarExtra` itself.
        .menuBarExtraAccess(isPresented: $manager.isPopoverPresented)
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Installed here, not in UsageManager, so the test process never gets an event monitor.
        StatusItemMenuController.shared.install()
    }
}
