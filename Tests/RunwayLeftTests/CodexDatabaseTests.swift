import XCTest
import SQLite3
@testable import RunwayLeft

/// Exercises the SQLite queries against a throwaway database shaped like
/// `~/.codex/state_5.sqlite` (only the columns the reader touches).
final class CodexDatabaseTests: XCTestCase {
    private var dbPath: String!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runwayleft-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("state_5.sqlite").path

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let schema = """
            CREATE TABLE threads (
                id INTEGER PRIMARY KEY,
                created_at INTEGER NOT NULL,
                model TEXT,
                tokens_used INTEGER NOT NULL
            );
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        // Two sessions on day A (one per model), one on day B, one with an empty model.
        let dayA = Self.epoch(year: 2026, month: 9, day: 2, hour: 10)
        let dayB = Self.epoch(year: 2026, month: 9, day: 3, hour: 9)
        let rows = [
            "(\(dayA), 'gpt-5.6', 100)",
            "(\(dayA + 3600), 'gpt-5.6', 250)",
            "(\(dayA + 7200), 'o4-mini', 40)",
            "(\(dayB), '', 7)",
            "(\(dayB + 60), 'gpt-5.6', 500)"
        ]
        let insert = "INSERT INTO threads (created_at, model, tokens_used) VALUES " + rows.joined(separator: ", ") + ";"
        XCTAssertEqual(sqlite3_exec(db, insert, nil, nil, nil), SQLITE_OK)
    }

    override func tearDownWithError() throws {
        if let path = dbPath {
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
    }

    /// Local-time epoch, matching SQLite's `'localtime'` modifier in the reader.
    private static func epoch(year: Int, month: Int, day: Int, hour: Int) -> Int64 {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        let date = Calendar.current.date(from: components)!
        return Int64(date.timeIntervalSince1970)
    }

    func testReadDatabaseProducesDailyPerModelBuckets() {
        var data = CodexUsageData()
        CodexDataReader(customPath: dbPath).readDatabase(into: &data)

        XCTAssertEqual(data.totalSessions, 5)
        XCTAssertEqual(data.totalTokens, 897)

        XCTAssertEqual(data.dailyUsage.map { $0.date }, ["2026-09-03", "2026-09-02"], "newest day first")
        XCTAssertEqual(data.dailyUsage.first?.tokensUsed, 507)

        let buckets = data.dailyModelTokens
        XCTAssertEqual(buckets.count, 4)

        func bucket(_ date: String, _ model: String) -> CodexDailyModelTokens? {
            buckets.first { $0.date == date && $0.modelName == model }
        }

        XCTAssertEqual(bucket("2026-09-02", "gpt-5.6")?.tokens, 350)
        XCTAssertEqual(bucket("2026-09-02", "gpt-5.6")?.sessionCount, 2)
        XCTAssertEqual(bucket("2026-09-02", "o4-mini")?.tokens, 40)
        XCTAssertEqual(bucket("2026-09-03", "gpt-5.6")?.tokens, 500)
        XCTAssertEqual(bucket("2026-09-03", "unknown")?.tokens, 7, "empty model names collapse to 'unknown'")

        // The all-time model table must agree with the sum of the daily buckets.
        let allTimeGpt = data.modelBreakdown.first { $0.modelName == "gpt-5.6" }?.totalTokens
        XCTAssertEqual(allTimeGpt, 850)
    }

    func testMissingDatabaseLeavesDataUntouched() {
        var data = CodexUsageData()
        CodexDataReader(customPath: "/nonexistent/path/state_5.sqlite").readDatabase(into: &data)
        XCTAssertTrue(data.dailyModelTokens.isEmpty)
        XCTAssertEqual(data.totalSessions, 0)
    }
}
