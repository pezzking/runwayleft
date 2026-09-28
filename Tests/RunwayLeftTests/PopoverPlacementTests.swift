import CoreGraphics
import XCTest
@testable import RunwayLeft

final class PopoverPlacementTests: XCTestCase {
    /// The built-in 16" display: 1117 pt tall, 33 pt menu bar, so the usable top is 1084.
    private let laptop = CGRect(x: 0, y: 0, width: 1677, height: 1084)
    private var top: CGFloat { laptop.maxY - PopoverPlacement.menuBarGap }

    func testWindowShrinksToShorterContentAndKeepsItsTop() {
        // Anchored at 1060 pt; the Models range then made the content 700 pt tall. The
        // window kept 1060, so the content sat centered in it, 180 pt below the menu bar.
        let window = CGRect(x: 1120, y: top - 1060, width: 456, height: 1060)
        let placed = PopoverPlacement.anchoredFrame(window, height: 700, visible: laptop)
        XCTAssertEqual(placed.maxY, top)
        XCTAssertEqual(placed.height, 700)
        XCTAssertEqual(placed.minX, 1120)
    }

    func testWindowGrowsToTallerContentAndKeepsItsTop() {
        let window = CGRect(x: 1120, y: top - 500, width: 456, height: 500)
        let placed = PopoverPlacement.anchoredFrame(window, height: 800, visible: laptop)
        XCTAssertEqual(placed.maxY, top)
        XCTAssertEqual(placed.height, 800)
    }

    func testSlidWindowIsPutBackUnderTheMenuBar() {
        let slid = CGRect(x: 1120, y: 100, width: 456, height: 600)
        let placed = PopoverPlacement.anchoredFrame(slid, height: 600, visible: laptop)
        XCTAssertEqual(placed.maxY, top)
    }

    func testContentTallerThanTheScreenIsCutToFit() {
        // The 1.13.2 report: a 1546 pt window, sized for the unplugged 38" display.
        let stale = CGRect(x: 1120, y: -427, width: 456, height: 1546)
        let placed = PopoverPlacement.anchoredFrame(stale, height: 1546, visible: laptop)
        XCTAssertEqual(placed.maxY, top)
        XCTAssertEqual(placed.minY, laptop.minY)
    }

    func testWindowPastTheRightEdgeIsPulledBackOnScreen() {
        let offRight = CGRect(x: 1500, y: 0, width: 456, height: 600)
        let placed = PopoverPlacement.anchoredFrame(offRight, height: 600, visible: laptop)
        XCTAssertEqual(placed.maxX, laptop.maxX)
    }

    func testSecondaryScreenUsesItsOwnCoordinates() {
        // A display arranged above the laptop has a non-zero origin.
        let upper = CGRect(x: -200, y: 1117, width: 3840, height: 1575)
        let window = CGRect(x: 900, y: 1500, width: 456, height: 700)
        let placed = PopoverPlacement.anchoredFrame(window, height: 700, visible: upper)
        XCTAssertEqual(placed.maxY, upper.maxY - PopoverPlacement.menuBarGap)
        XCTAssertEqual(placed.height, 700)
    }

    func testAlreadyPlacedWindowIsUnchanged() {
        let placed = CGRect(x: 1120, y: top - 600, width: 456, height: 600)
        XCTAssertEqual(PopoverPlacement.anchoredFrame(placed, height: 600, visible: laptop), placed)
    }
}
