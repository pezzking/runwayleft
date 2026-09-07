import XCTest
@testable import RunwayLeft

final class MenuBarContextMenuTests: XCTestCase {
    private func item(_ title: String, in items: [MenuBarContextMenu.Item]) -> MenuBarContextMenu.Item? {
        items.first { $0.title == title }
    }

    func testOffersSettingsAndQuit() {
        let items = MenuBarContextMenu.items(.init())

        XCTAssertEqual(item("Settings…", in: items)?.action, .openTab(.settings))
        XCTAssertEqual(item("Open Overview", in: items)?.action, .openTab(.overview))

        let quit = item("Quit RunwayLeft", in: items)
        XCTAssertEqual(quit?.action, .quit)
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(items.last, quit, "Quit is the last item, as in every menu bar app")
    }

    func testRefreshIsDisabledWhileRefreshing() {
        XCTAssertEqual(item("Refresh Now", in: MenuBarContextMenu.items(.init(isRefreshing: false)))?.isEnabled, true)
        XCTAssertEqual(item("Refresh Now", in: MenuBarContextMenu.items(.init(isRefreshing: true)))?.isEnabled, false)
    }

    func testLaunchAtLoginCheckmarkTracksState() {
        let off = item("Launch at Login", in: MenuBarContextMenu.items(.init(launchAtLogin: false)))
        let on = item("Launch at Login", in: MenuBarContextMenu.items(.init(launchAtLogin: true)))
        XCTAssertEqual(off?.isChecked, false)
        XCTAssertEqual(on?.isChecked, true)
        XCTAssertEqual(on?.action, .toggleLaunchAtLogin)
    }

    func testSeparatorsNeverLeadTrailOrDouble() {
        let items = MenuBarContextMenu.items(.init())
        XCTAssertFalse(items.first?.isSeparator ?? true)
        XCTAssertFalse(items.last?.isSeparator ?? true)
        for (previous, next) in zip(items, items.dropFirst()) {
            XCTAssertFalse(previous.isSeparator && next.isSeparator, "two separators in a row")
        }
        XCTAssertGreaterThanOrEqual(items.filter(\.isSeparator).count, 1)
    }
}
