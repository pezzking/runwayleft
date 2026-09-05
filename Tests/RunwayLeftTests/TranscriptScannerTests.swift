import XCTest
@testable import RunwayLeft

final class TranscriptScannerTests: XCTestCase {
    private var directory: URL!
    private let calendar = Calendar.current
    private var now: Date { Date() }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runwayleft-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("project-a"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func userLine(session: String = "s1", at date: Date? = nil, sidechain: Bool = false) -> String {
        """
        {"parentUuid":null,"isSidechain":\(sidechain),"type":"user","sessionId":"\(session)","timestamp":"\(iso(date ?? now))","message":{"role":"user","content":"hi"}}
        """
    }

    private func assistantLine(id: String, model: String = "claude-fable-5-1", input: Int = 100, output: Int = 10, cacheCreate: Int = 5, toolUses: Int = 0, session: String = "s1", at date: Date? = nil) -> String {
        let content = (0..<toolUses).map { _ in #"{"type":"tool_use","id":"t","name":"Bash","input":{}}"# }.joined(separator: ",")
        return """
        {"parentUuid":"p","isSidechain":false,"type":"assistant","sessionId":"\(session)","timestamp":"\(iso(date ?? now))","message":{"model":"\(model)","id":"\(id)","type":"message","role":"assistant","content":[\(content)],"usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheCreate),"cache_read_input_tokens":99999}}}
        """
    }

    private func write(_ lines: [String], to name: String, trailingNewline: Bool = true) throws -> URL {
        let url = directory.appendingPathComponent("project-a/\(name).jsonl")
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try text.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private func append(_ lines: [String], to url: URL, trailingNewline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        // Make sure the modification date moves even when the write is sub-second.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    // MARK: - Tests

    func testFullScanCountsMessagesToolsSessionsAndTokensWithoutCacheReads() throws {
        _ = try write([
            userLine(session: "s1"),
            assistantLine(id: "m1", input: 100, output: 10, cacheCreate: 5, toolUses: 2, session: "s1"),
            userLine(session: "s2"),
            assistantLine(id: "m2", model: "claude-sonnet-5", input: 20, output: 2, cacheCreate: 0, session: "s2"),
            userLine(session: "side", sidechain: true)
        ], to: "one")

        let scanner = TranscriptScanner(directory: directory.path)
        let stats = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))

        XCTAssertEqual(stats.messageCount, 5)
        XCTAssertEqual(stats.toolCallCount, 2)
        XCTAssertEqual(stats.sessionCount, 2, "sidechain lines do not count as sessions")
        XCTAssertEqual(stats.tokensByModel["claude-fable-5-1"], 115)
        XCTAssertEqual(stats.tokensByModel["claude-sonnet-5"], 22)
        XCTAssertEqual(stats.totalTokens, 137)
    }

    func testSecondPassReadsOnlyAppendedBytes() throws {
        let url = try write([userLine(), assistantLine(id: "m1")], to: "one")
        let scanner = TranscriptScanner(directory: directory.path)

        let first = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(first.messageCount, 2)
        let firstBytes = scanner.lastPassBytes
        XCTAssertGreaterThan(firstBytes, 0)

        // Unchanged file: nothing is read.
        _ = scanner.scan(now: now, calendar: calendar)
        XCTAssertEqual(scanner.lastPassBytes, 0)
        XCTAssertEqual(scanner.lastPassFilesRead, 0)

        // Appended lines: only the delta is read, totals accumulate.
        let extra = assistantLine(id: "m2", input: 50, output: 0, cacheCreate: 0)
        try append([extra], to: url)
        let second = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(second.messageCount, 3)
        XCTAssertEqual(second.totalTokens, 115 + 50)
        XCTAssertEqual(scanner.lastPassBytes, extra.utf8.count + 1)
        XCTAssertEqual(scanner.lastPassFilesRead, 1)
    }

    func testPartialTrailingLineIsRetriedNotLost() throws {
        let complete = assistantLine(id: "m1")
        let partial = assistantLine(id: "m2", input: 500, output: 0, cacheCreate: 0)
        let cut = String(partial.prefix(partial.count / 2))

        let url = try write([userLine(), complete], to: "one")
        try append([cut], to: url, trailingNewline: false)

        let scanner = TranscriptScanner(directory: directory.path)
        let first = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(first.totalTokens, 115, "the half-written line is not counted yet")

        // The writer finishes the line.
        try append([String(partial.dropFirst(partial.count / 2))], to: url)
        let second = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(second.totalTokens, 115 + 500, "the completed line is counted exactly once")
        XCTAssertEqual(second.messageCount, 3)
    }

    func testRepeatedMessageIDsCountOnce() throws {
        _ = try write([
            assistantLine(id: "same", input: 100, output: 0, cacheCreate: 0),
            assistantLine(id: "same", input: 100, output: 0, cacheCreate: 0),
            assistantLine(id: "same", input: 100, output: 0, cacheCreate: 0)
        ], to: "one")

        let stats = try XCTUnwrap(TranscriptScanner(directory: directory.path).scan(now: now, calendar: calendar))
        XCTAssertEqual(stats.totalTokens, 100)
        XCTAssertEqual(stats.messageCount, 3, "every streamed line is still a message")
    }

    func testMessageIDsAreDeduplicatedAcrossFiles() throws {
        // A resumed session replays earlier turns into a second transcript.
        _ = try write([assistantLine(id: "shared", input: 100, output: 0, cacheCreate: 0, session: "s1")], to: "original")
        _ = try write([
            assistantLine(id: "shared", input: 100, output: 0, cacheCreate: 0, session: "s2"),
            assistantLine(id: "fresh", input: 1, output: 0, cacheCreate: 0, session: "s2")
        ], to: "resumed")

        let scanner = TranscriptScanner(directory: directory.path)
        let stats = try XCTUnwrap(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(stats.totalTokens, 101, "the replayed message counts once")
        XCTAssertEqual(stats.sessionCount, 2)

        // Appending to one file later must not re-count IDs already seen in the other.
        let resumed = directory.appendingPathComponent("project-a/resumed.jsonl")
        try append([assistantLine(id: "shared", input: 100, output: 0, cacheCreate: 0, session: "s2")], to: resumed)
        XCTAssertEqual(scanner.scan(now: now, calendar: calendar)?.totalTokens, 101)
        XCTAssertFalse(scanner.lastPassWasFullRescan)
    }

    func testDeletedFileTriggersFullRescan() throws {
        let doomed = try write([assistantLine(id: "gone", input: 500, output: 0, cacheCreate: 0)], to: "doomed")
        _ = try write([assistantLine(id: "kept", input: 5, output: 0, cacheCreate: 0)], to: "kept")

        let scanner = TranscriptScanner(directory: directory.path)
        XCTAssertEqual(scanner.scan(now: now, calendar: calendar)?.totalTokens, 505)

        try FileManager.default.removeItem(at: doomed)
        XCTAssertEqual(scanner.scan(now: now, calendar: calendar)?.totalTokens, 5)
        XCTAssertTrue(scanner.lastPassWasFullRescan)
    }

    func testLinesFromBeforeTodayAreIgnored() throws {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        _ = try write([
            assistantLine(id: "old", input: 1_000, output: 0, cacheCreate: 0, at: yesterday),
            assistantLine(id: "new", input: 10, output: 0, cacheCreate: 0)
        ], to: "one")

        let stats = try XCTUnwrap(TranscriptScanner(directory: directory.path).scan(now: now, calendar: calendar))
        XCTAssertEqual(stats.totalTokens, 10)
        XCTAssertEqual(stats.messageCount, 1)
    }

    func testTruncatedFileIsReparsedFromTheStart() throws {
        let url = try write([assistantLine(id: "a", input: 100, output: 0, cacheCreate: 0), assistantLine(id: "b", input: 100, output: 0, cacheCreate: 0)], to: "one")
        let scanner = TranscriptScanner(directory: directory.path)
        XCTAssertEqual(scanner.scan(now: now, calendar: calendar)?.totalTokens, 200)

        // Rewritten shorter, with different content.
        try (assistantLine(id: "c", input: 7, output: 0, cacheCreate: 0) + "\n").write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        XCTAssertEqual(scanner.scan(now: now, calendar: calendar)?.totalTokens, 7)
    }

    func testFilesNotModifiedTodayAreSkippedAndNoMessagesYieldsNil() throws {
        let url = try write([assistantLine(id: "a")], to: "stale")
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: url.path)

        let scanner = TranscriptScanner(directory: directory.path)
        XCTAssertNil(scanner.scan(now: now, calendar: calendar))
        XCTAssertEqual(scanner.lastPassFilesRead, 0)
    }

    func testMalformedLinesAreSkipped() throws {
        _ = try write(["not json", "{\"type\":\"assistant\"}", assistantLine(id: "ok", input: 3, output: 0, cacheCreate: 0)], to: "one")
        let stats = try XCTUnwrap(TranscriptScanner(directory: directory.path).scan(now: now, calendar: calendar))
        XCTAssertEqual(stats.totalTokens, 3)
        XCTAssertEqual(stats.messageCount, 1)
    }

    // MARK: - Equivalence against the previous full-parse implementation

    /// Set RUNWAY_REAL_TRANSCRIPTS=1 to compare the incremental scanner with a
    /// straight port of the old whole-file parser over the real ~/.claude/projects.
    func testIncrementalScannerMatchesReferenceOnRealTranscripts() throws {
        guard ProcessInfo.processInfo.environment["RUNWAY_REAL_TRANSCRIPTS"] == "1" else {
            throw XCTSkip("set RUNWAY_REAL_TRANSCRIPTS=1 to run against real data")
        }
        let projects = NSString(string: "~/.claude/projects").expandingTildeInPath
        let at = Date()

        let referenceStart = Date()
        let reference = Self.referenceScan(directory: projects, now: at, calendar: calendar)
        let referenceSeconds = Date().timeIntervalSince(referenceStart)

        let scanner = TranscriptScanner(directory: projects)
        let coldStart = Date()
        let cold = scanner.scan(now: at, calendar: calendar)
        let coldSeconds = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        let warm = scanner.scan(now: at, calendar: calendar)
        let warmSeconds = Date().timeIntervalSince(warmStart)

        print("""
        [equivalence] reference \(String(format: "%.2f", referenceSeconds))s, cold \(String(format: "%.2f", coldSeconds))s, warm \(String(format: "%.3f", warmSeconds))s (\(scanner.lastPassBytes) bytes)
        [equivalence] reference tokens=\(reference?.totalTokens ?? 0) msgs=\(reference?.messageCount ?? 0) tools=\(reference?.toolCallCount ?? 0) sessions=\(reference?.sessionCount ?? 0)
        [equivalence] scanner   tokens=\(cold?.totalTokens ?? 0) msgs=\(cold?.messageCount ?? 0) tools=\(cold?.toolCallCount ?? 0) sessions=\(cold?.sessionCount ?? 0)
        """)

        XCTAssertEqual(cold?.tokensByModel, reference?.tokensByModel)
        XCTAssertEqual(cold?.messageCount, reference?.messageCount)
        XCTAssertEqual(cold?.toolCallCount, reference?.toolCallCount)
        XCTAssertEqual(cold?.sessionCount, reference?.sessionCount)
        XCTAssertEqual(warm, cold, "a second pass over unchanged files must reproduce the totals")
        XCTAssertLessThan(warmSeconds, max(0.5, coldSeconds / 10), "the warm pass must be at least 10x cheaper")
    }

    /// The whole-file parser this scanner replaced, kept as the oracle.
    private static func referenceScan(directory: String, now: Date, calendar: Calendar) -> TranscriptScanner.DayStats? {
        let startOfDay = calendar.startOfDay(for: now)
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()

        var seenMessageIDs = Set<String>()
        var tokenTotals: [String: Int64] = [:]
        var sessionIDs = Set<String>()
        var messageCount = 0
        var toolCallCount = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modDate >= startOfDay else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = obj["type"] as? String,
                      type == "user" || type == "assistant",
                      obj["isMeta"] as? Bool != true,
                      let timestampStr = obj["timestamp"] as? String,
                      let timestamp = isoFormatter.date(from: timestampStr) ?? isoFormatterNoFraction.date(from: timestampStr),
                      timestamp >= startOfDay else { continue }

                messageCount += 1
                if obj["isSidechain"] as? Bool != true, let sessionID = obj["sessionId"] as? String {
                    sessionIDs.insert(sessionID)
                }
                guard let message = obj["message"] as? [String: Any] else { continue }
                if type == "assistant", let content = message["content"] as? [[String: Any]] {
                    toolCallCount += content.filter { $0["type"] as? String == "tool_use" }.count
                }
                guard type == "assistant",
                      let usage = message["usage"] as? [String: Any],
                      let model = message["model"] as? String else { continue }
                let messageID = message["id"] as? String ?? UUID().uuidString
                guard seenMessageIDs.insert(messageID).inserted else { continue }
                let input = (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? NSNumber)?.int64Value ?? 0
                tokenTotals[model, default: 0] += input + output + cacheCreate
            }
        }

        guard messageCount > 0 else { return nil }
        return TranscriptScanner.DayStats(
            date: DayFormat.string(from: now, calendar: calendar),
            tokensByModel: tokenTotals,
            messageCount: messageCount,
            toolCallCount: toolCallCount,
            sessionCount: sessionIDs.count
        )
    }
}
