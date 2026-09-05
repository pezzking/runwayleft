import Foundation

/// Incrementally tallies today's Claude Code activity from the JSONL
/// transcripts under `~/.claude/projects`.
///
/// Transcripts are append-only, so each file is read from the byte offset
/// where the previous pass stopped, and files whose size and modification
/// date are unchanged are skipped outright. Only newline-terminated lines are
/// consumed; a half-written trailing line stays unread until the next pass.
///
/// Message IDs are de-duplicated across the whole day, not per file: a resumed
/// session replays earlier turns into a new transcript with the same IDs. That
/// makes per-file totals impossible to subtract, so if any file shrinks or
/// disappears the day is re-scanned from scratch. The cache is keyed by the
/// local calendar day and cleared at rollover.
///
/// Not thread-safe: `UsageManager` serializes refreshes on one background queue.
final class TranscriptScanner {
    struct DayStats: Equatable {
        var date: String
        var tokensByModel: [String: Int64] = [:]
        var messageCount = 0
        var toolCallCount = 0
        var sessionCount = 0

        var totalTokens: Int64 { tokensByModel.values.reduce(0, +) }
    }

    private struct DayAccumulator {
        var tokensByModel: [String: Int64] = [:]
        var messageCount = 0
        var toolCallCount = 0
        var sessionIDs = Set<String>()
        var seenMessageIDs = Set<String>()
    }

    private struct FileState {
        var offset: UInt64 = 0
        var size: UInt64 = 0
        var modified: Date = .distantPast
    }

    private struct Candidate {
        let path: String
        let size: UInt64
        let modified: Date
    }

    let directory: String
    private var dayKey: String?
    private var files: [String: FileState] = [:]
    private var day = DayAccumulator()

    /// Work done by the most recent `scan`, for tests and diagnostics.
    private(set) var lastPassBytes = 0
    private(set) var lastPassFilesRead = 0
    private(set) var lastPassWasFullRescan = false

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()

    init(directory: String) {
        self.directory = directory
    }

    /// Returns today's totals, or nil when no message was recorded today.
    func scan(now: Date = Date(), calendar: Calendar = .current) -> DayStats? {
        let startOfDay = calendar.startOfDay(for: now)
        let today = DayFormat.string(from: now, calendar: calendar)

        lastPassBytes = 0
        lastPassFilesRead = 0
        lastPassWasFullRescan = false

        if dayKey != today {
            reset()
            dayKey = today
        }

        let candidates = collectCandidates(modifiedSince: startOfDay)
        let candidateSizes = Dictionary(uniqueKeysWithValues: candidates.map { ($0.path, $0.size) })

        // A vanished or truncated file invalidates the day's de-duplication.
        let invalidated = files.contains { path, state in
            guard let size = candidateSizes[path] else { return true }
            return size < state.offset
        }
        if invalidated {
            reset()
            lastPassWasFullRescan = true
        }

        for candidate in candidates {
            if let existing = files[candidate.path], existing.size == candidate.size, existing.modified == candidate.modified {
                continue
            }

            var state = files[candidate.path] ?? FileState()

            guard let handle = FileHandle(forReadingAtPath: candidate.path) else { continue }
            defer { try? handle.close() }

            if state.offset > 0 {
                guard (try? handle.seek(toOffset: state.offset)) != nil else { continue }
            }

            let data = handle.readDataToEndOfFile()
            lastPassBytes += data.count
            lastPassFilesRead += 1

            let consumed = consume(data, startOfDay: startOfDay)
            state.offset += UInt64(consumed)
            state.size = candidate.size
            state.modified = candidate.modified
            files[candidate.path] = state
        }

        guard day.messageCount > 0 else { return nil }

        return DayStats(
            date: today,
            tokensByModel: day.tokensByModel,
            messageCount: day.messageCount,
            toolCallCount: day.toolCallCount,
            sessionCount: day.sessionIDs.count
        )
    }

    private func reset() {
        files.removeAll()
        day = DayAccumulator()
    }

    private func collectCandidates(modifiedSince startOfDay: Date) -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [Candidate] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  modified >= startOfDay else { continue }
            result.append(Candidate(path: url.path, size: UInt64(values.fileSize ?? 0), modified: modified))
        }
        // Stable order keeps which file "wins" a duplicated message ID deterministic.
        return result.sorted { $0.path < $1.path }
    }

    /// Parses every complete line and returns the number of bytes consumed,
    /// which ends at the last newline so a partial trailing line is retried.
    private func consume(_ data: Data, startOfDay: Date) -> Int {
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return 0 }

        var lineStart = data.startIndex
        while lineStart <= lastNewline {
            let lineEnd = data[lineStart...lastNewline].firstIndex(of: 0x0A) ?? lastNewline
            if lineEnd > lineStart {
                let line = data.subdata(in: lineStart..<lineEnd)
                autoreleasepool {
                    parse(line, startOfDay: startOfDay)
                }
            }
            lineStart = lineEnd + 1
        }

        return lastNewline - data.startIndex + 1
    }

    private func parse(_ line: Data, startOfDay: Date) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String,
              type == "user" || type == "assistant",
              obj["isMeta"] as? Bool != true,
              let timestampStr = obj["timestamp"] as? String,
              let timestamp = Self.isoFractional.date(from: timestampStr) ?? Self.isoPlain.date(from: timestampStr),
              timestamp >= startOfDay else { return }

        day.messageCount += 1

        if obj["isSidechain"] as? Bool != true, let sessionID = obj["sessionId"] as? String {
            day.sessionIDs.insert(sessionID)
        }

        guard let message = obj["message"] as? [String: Any] else { return }

        if type == "assistant", let content = message["content"] as? [[String: Any]] {
            day.toolCallCount += content.filter { $0["type"] as? String == "tool_use" }.count
        }

        guard type == "assistant",
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String else { return }

        // Streaming/tool-use turns log the same message id multiple times with
        // an identical cumulative usage snapshot, and resumed sessions replay
        // earlier turns into a new file; count each id once per day.
        let messageID = message["id"] as? String ?? UUID().uuidString
        guard day.seenMessageIDs.insert(messageID).inserted else { return }

        let input = (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0
        let output = (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? NSNumber)?.int64Value ?? 0

        // Excludes cache_read_input_tokens, matching stats-cache.json's daily totals.
        day.tokensByModel[model, default: 0] += input + output + cacheCreate
    }
}
