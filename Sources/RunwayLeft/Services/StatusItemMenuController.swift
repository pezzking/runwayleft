import AppKit
import SwiftUI

/// Shows a context menu when the status item is right-clicked or Control-clicked.
///
/// `MenuBarExtra` has no right-click hook and its button treats a right click like a
/// left one, so a local event monitor swallows the event and pops the menu instead.
/// The button comes from the event's own window, no private API involved.
///
/// Menu items that open the popover set `UsageManager.isPopoverPresented`. The
/// MenuBarExtraAccess binding on the scene turns that into the actual open and, through
/// its own key-window observers, keeps the flag in sync when a click opens or closes the
/// popover. A single write is therefore all that belongs here. Do not mirror the window's
/// visibility back into the flag and do not intercept clicks to close it: both were tried,
/// and both desynchronize the library's button state from the real window, after which
/// clicking the status item stops toggling reliably. See the gotcha in CLAUDE.md.
final class StatusItemMenuController: NSObject {
    static let shared = StatusItemMenuController()

    private var monitor: Any?
    private var items: [MenuBarContextMenu.Item] = []

    private override init() {
        super.init()
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, Self.isContextClick(event), let button = Self.statusBarButton(under: event) else {
                return event
            }
            self.showMenu(below: button)
            // Swallowed on purpose: passing it on would also toggle the popover.
            return nil
        }
    }

    private static func isContextClick(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    /// The status bar button the event landed on, if it landed on one at all. Each
    /// status item lives in its own window, so the event's window is enough to tell.
    private static func statusBarButton(under event: NSEvent) -> NSStatusBarButton? {
        guard let contentView = event.window?.contentView,
              let button = firstStatusBarButton(in: contentView) else { return nil }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point) ? button : nil
    }

    private static func firstStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = firstStatusBarButton(in: subview) { return button }
        }
        return nil
    }

    private func showMenu(below button: NSStatusBarButton) {
        let manager = UsageManager.shared
        manager.refreshLaunchAtLoginStatus()
        items = MenuBarContextMenu.items(.init(isRefreshing: manager.isRefreshing, launchAtLogin: manager.launchAtLogin))

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: item.title, action: #selector(handleMenuItem(_:)), keyEquivalent: item.keyEquivalent)
            menuItem.target = self
            menuItem.tag = index
            menuItem.isEnabled = item.isEnabled
            menuItem.state = item.isChecked ? .on : .off
            menu.addItem(menuItem)
        }

        // The button is flipped, so maxY is its bottom edge and the menu hangs below the bar.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func handleMenuItem(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag), let action = items[sender.tag].action else { return }
        let manager = UsageManager.shared
        switch action {
        case .refresh:
            manager.refreshData(force: true)
        case .openTab(let tab):
            manager.selectedTab = tab
            // Opening while the menu is still tearing down is ignored, so do it once the
            // menu has closed. The library keeps the flag in sync, so a plain assignment
            // is right even when it is already true.
            DispatchQueue.main.async {
                manager.isPopoverPresented = true
            }
        case .toggleLaunchAtLogin:
            manager.setLaunchAtLogin(!manager.launchAtLogin)
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
