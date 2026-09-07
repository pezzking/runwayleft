import Foundation

/// What the status item's right-click menu offers. Pure so tests can check it;
/// `StatusItemMenuController` turns the items into an `NSMenu`.
enum MenuBarContextMenu {
    enum Action: Equatable {
        case refresh
        case openTab(AppTab)
        case toggleLaunchAtLogin
        case quit
    }

    struct Item: Equatable {
        var title: String
        /// `nil` marks a separator.
        var action: Action?
        var isEnabled: Bool = true
        var isChecked: Bool = false
        var keyEquivalent: String = ""

        static let separator = Item(title: "", action: nil)
        var isSeparator: Bool { action == nil }
    }

    struct Context: Equatable {
        var isRefreshing: Bool = false
        var launchAtLogin: Bool = false
    }

    static func items(_ context: Context) -> [Item] {
        [
            Item(title: "Refresh Now", action: .refresh, isEnabled: !context.isRefreshing),
            .separator,
            Item(title: "Open Overview", action: .openTab(.overview)),
            Item(title: "Settings…", action: .openTab(.settings)),
            Item(title: "Launch at Login", action: .toggleLaunchAtLogin, isChecked: context.launchAtLogin),
            .separator,
            Item(title: "Quit RunwayLeft", action: .quit, keyEquivalent: "q"),
        ]
    }
}
