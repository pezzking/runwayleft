import AppKit
import SwiftUI

/// Keeps the popover window hanging from the menu bar at the content's height. Placed
/// in the popover's background, it finds its own window and, whenever that window
/// opens, resizes, lands on another screen, or the content height changes, clamps the
/// height to that screen and re-frames the window with `PopoverPlacement`.
///
/// The `MenuBarExtra` window does not shrink when its content does, so a shorter tab
/// (the Models range toggle) or a smaller screen left the content centered in a taller,
/// transparent window, well below the menu bar. The window's own screen is also the
/// source of truth for the clamp: a cached screen height went stale when a monitor was
/// unplugged. This only reads and sets the frame; it never touches
/// `isPopoverPresented`, which belongs to MenuBarExtraAccess (see CLAUDE.md).
struct PopoverWindowAnchor: NSViewRepresentable {
    let manager: UsageManager
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> AnchorView {
        AnchorView(manager: manager)
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        guard nsView.contentHeight != contentHeight else { return }
        nsView.contentHeight = contentHeight
        // After SwiftUI finishes this layout pass, so the frame change does not re-enter it.
        DispatchQueue.main.async { nsView.anchor() }
    }

    final class AnchorView: NSView {
        private let manager: UsageManager
        var contentHeight: CGFloat = 0
        private var observers: [NSObjectProtocol] = []

        init(manager: UsageManager) {
            self.manager = manager
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        deinit { stopObserving() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.anchor()
                }
            }
            anchor()
        }

        private func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        func anchor() {
            guard let window, let screen = window.screen, contentHeight > 0 else { return }
            let visible = screen.visibleFrame
            // Shrinks the SwiftUI frame to this screen; the new height arrives through
            // `updateNSView` and lands here again.
            manager.refreshScreenHeight(visible.height)
            let chrome = window.frame.height - window.contentLayoutRect.height
            let target = PopoverPlacement.anchoredFrame(window.frame, height: contentHeight + chrome, visible: visible)
            if target != window.frame {
                window.setFrame(target, display: true)
            }
        }
    }
}
