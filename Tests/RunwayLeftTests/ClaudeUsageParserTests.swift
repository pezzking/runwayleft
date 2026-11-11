import XCTest
@testable import RunwayLeft

final class ClaudeUsageParserTests: XCTestCase {
    func testParsesSessionAndWeeklyWindows() {
        var data = ClaudeUsageData()
        ClaudeDataReader.parseUsageText("""
        Current session: 8% used · resets 5:19pm (Europe/Amsterdam)
        Current week (all models): 17% used · resets Sep 6 at 6:59pm (Europe/Amsterdam)
        Current week (Fable): 72% used · resets Sep 6 at 6:59pm (Europe/Amsterdam)
        """, into: &data)

        XCTAssertTrue(data.hasLiveStatus)
        XCTAssertEqual(data.sessionUsedPct, 8)
        XCTAssertEqual(data.sessionReset, "5:19pm (Europe/Amsterdam)")
        XCTAssertEqual(data.weekAllModelsPct, 17)
        XCTAssertEqual(data.weekFablePct, 72)
        XCTAssertEqual(data.weekModelLabel, "Fable")
    }

    func testSessionAtZeroIsStillAWindow() {
        var data = ClaudeUsageData()
        ClaudeDataReader.parseUsageText("Current session: 0% used · resets 5:19pm", into: &data)
        XCTAssertEqual(data.sessionUsedPct, 0)
    }

    /// Plans without the five-hour cap report only the weekly lines.
    func testPlanWithoutSessionWindowLeavesSessionNil() {
        var data = ClaudeUsageData()
        ClaudeDataReader.parseUsageText("""
        You are currently using your subscription to power your Claude Code usage

        Current week (all models): 10% used · resets Nov 15 at 6pm (Europe/Amsterdam)
        Current week (Fable): 7% used · resets Nov 15 at 6pm (Europe/Amsterdam)

        What's contributing to your usage?
        Last 24h · 1351 requests · 8 sessions
        """, into: &data)

        XCTAssertTrue(data.hasLiveStatus)
        XCTAssertNil(data.sessionUsedPct)
        XCTAssertEqual(data.sessionReset, "")
        XCTAssertEqual(data.weekAllModelsPct, 10)
        XCTAssertEqual(data.weekAllModelsReset, "Nov 15 at 6pm (Europe/Amsterdam)")
        XCTAssertEqual(data.weekFablePct, 7)
        XCTAssertEqual(data.weekModelLabel, "Fable")
    }
}
