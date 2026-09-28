import CoreGraphics

/// Where the popover window belongs on its screen. Pure geometry, no AppKit, so the
/// rule is tested directly.
///
/// The `MenuBarExtra` window keeps its height when the content shrinks, which left the
/// content centered in a taller, transparent window below the menu bar. The frame is
/// therefore set from the content height after every change: top edge just under the
/// menu bar, height no taller than the usable screen, and the whole window on screen.
enum PopoverPlacement {
    /// Gap between the menu bar and the popover's top edge, as AppKit places it on open.
    static let menuBarGap: CGFloat = 2

    /// `height` is what the content needs; `visible` is the screen's `visibleFrame`,
    /// whose top is the menu bar's bottom edge. Only `frame`'s x and width are kept.
    static func anchoredFrame(_ frame: CGRect, height: CGFloat, visible: CGRect) -> CGRect {
        let top = visible.maxY - menuBarGap
        let height = min(height, top - visible.minY)
        let width = min(frame.width, visible.width)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}
