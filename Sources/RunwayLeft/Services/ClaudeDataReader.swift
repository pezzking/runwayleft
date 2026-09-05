import Foundation

class ClaudeDataReader {
    static let shared = ClaudeDataReader()

    /// The `claude -p /usage` call costs about two seconds of CPU, so it runs
    /// at most this often unless the user presses Refresh.
    static let liveStatusInterval: TimeInterval = 300
    /// A cached live snapshot older than this is discarded rather than shown.
    static let liveStatusMaxAge: TimeInterval = 1800

    private let statsFilePath: String
    private let claudeBinaryPath: String
    private let scanner: TranscriptScanner

    /// Last successful live quota reading and when it was taken.
    private var liveSnapshot: LiveSnapshot?
    private var liveSnapshotAt: Date?
    /// When the CLI was last attempted, successful or not.
    private var liveAttemptedAt: Date?

    struct LiveSnapshot {
        var sessionUsedPct: Double
        var sessionReset: String
        var weekAllModelsPct: Double
        var weekAllModelsReset: String
        var weekFablePct: Double
        var weekFableReset: String
        var weekModelLabel: String

        init(from data: ClaudeUsageData) {
            sessionUsedPct = data.sessionUsedPct
            sessionReset = data.sessionReset
            weekAllModelsPct = data.weekAllModelsPct
            weekAllModelsReset = data.weekAllModelsReset
            weekFablePct = data.weekFablePct
            weekFableReset = data.weekFableReset
            weekModelLabel = data.weekModelLabel
        }

        func apply(to data: inout ClaudeUsageData) {
            data.sessionUsedPct = sessionUsedPct
            data.sessionReset = sessionReset
            data.weekAllModelsPct = weekAllModelsPct
            data.weekAllModelsReset = weekAllModelsReset
            data.weekFablePct = weekFablePct
            data.weekFableReset = weekFableReset
            data.weekModelLabel = weekModelLabel
            data.hasLiveStatus = true
        }
    }

    init(customPath: String? = nil, projectsDirectory: String? = nil) {
        if let path = customPath {
            self.statsFilePath = path
        } else {
            self.statsFilePath = NSString(string: "~/.claude/stats-cache.json").expandingTildeInPath
        }

        let projects = projectsDirectory ?? NSString(string: "~/.claude/projects").expandingTildeInPath
        self.scanner = TranscriptScanner(directory: projects)

        let candidates = [
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        self.claudeBinaryPath = candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? ""
    }

    /// - Parameter forceLive: re-run the `claude` CLI even if the cached
    ///   quota snapshot is still fresh (the Refresh button passes true).
    func fetchUsageData(forceLive: Bool = false) -> ClaudeUsageData {
        var data = ClaudeUsageData()
        let fileURL = URL(fileURLWithPath: statsFilePath)

        // 1. Read JSON stats-cache.json for historical daily tokens and messages
        if FileManager.default.fileExists(atPath: statsFilePath),
           let jsonData = try? Data(contentsOf: fileURL),
           let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

            data.lastComputedDate = root["lastComputedDate"] as? String ?? ""
            data.totalSessions = root["totalSessions"] as? Int ?? 0
            data.totalMessages = root["totalMessages"] as? Int ?? 0

            if let activityArray = root["dailyActivity"] as? [[String: Any]] {
                data.dailyActivity = activityArray.compactMap { dict in
                    guard let date = dict["date"] as? String else { return nil }
                    return ClaudeDailyActivity(
                        date: date,
                        messageCount: dict["messageCount"] as? Int ?? 0,
                        sessionCount: dict["sessionCount"] as? Int ?? 0,
                        toolCallCount: dict["toolCallCount"] as? Int ?? 0
                    )
                }
            }

            if let tokensArray = root["dailyModelTokens"] as? [[String: Any]] {
                data.dailyModelTokens = tokensArray.compactMap { dict in
                    guard let date = dict["date"] as? String,
                          let rawByModel = dict["tokensByModel"] as? [String: Any] else { return nil }

                    var byModel: [String: Int64] = [:]
                    for (k, v) in rawByModel {
                        if let valNum = v as? NSNumber {
                            byModel[k] = valNum.int64Value
                        }
                    }
                    return ClaudeDailyModelTokens(date: date, tokensByModel: byModel)
                }
            }

            if let modelDict = root["modelUsage"] as? [String: [String: Any]] {
                data.modelUsage = modelDict.map { (modelName, details) in
                    let input = (details["inputTokens"] as? NSNumber)?.int64Value ?? 0
                    let output = (details["outputTokens"] as? NSNumber)?.int64Value ?? 0
                    let cacheRead = (details["cacheReadInputTokens"] as? NSNumber)?.int64Value ?? 0
                    let cacheCreate = (details["cacheCreationInputTokens"] as? NSNumber)?.int64Value ?? 0

                    return ClaudeModelDetail(
                        modelName: modelName,
                        inputTokens: input,
                        outputTokens: output,
                        cacheReadInputTokens: cacheRead,
                        cacheCreationInputTokens: cacheCreate
                    )
                }.sorted { $0.totalTokens > $1.totalTokens }
            }
        }

        // 2. Today's tokens and activity live from session transcripts, since
        // stats-cache.json is only refreshed periodically and can lag by a day.
        mergeTodayLiveStatsFromTranscripts(&data)

        // 3. Live subscription status from the claude CLI, throttled.
        applyLiveStatus(&data, force: forceLive)

        return data
    }

    private func mergeTodayLiveStatsFromTranscripts(_ data: inout ClaudeUsageData) {
        guard let today = scanner.scan() else { return }

        if !today.tokensByModel.isEmpty {
            data.dailyModelTokens.removeAll { $0.date == today.date }
            data.dailyModelTokens.append(ClaudeDailyModelTokens(date: today.date, tokensByModel: today.tokensByModel))
        }

        data.dailyActivity.removeAll { $0.date == today.date }
        data.dailyActivity.append(ClaudeDailyActivity(
            date: today.date,
            messageCount: today.messageCount,
            sessionCount: today.sessionCount,
            toolCallCount: today.toolCallCount
        ))
    }

    private func applyLiveStatus(_ data: inout ClaudeUsageData, force: Bool) {
        let now = Date()
        let attemptIsFresh = liveAttemptedAt.map { now.timeIntervalSince($0) < Self.liveStatusInterval } ?? false

        if force || !attemptIsFresh {
            var probe = ClaudeUsageData()
            fetchLiveCLIUsage(&probe)
            liveAttemptedAt = now

            if probe.hasLiveStatus {
                liveSnapshot = LiveSnapshot(from: probe)
                liveSnapshotAt = now
            } else if let takenAt = liveSnapshotAt, now.timeIntervalSince(takenAt) > Self.liveStatusMaxAge {
                liveSnapshot = nil
                liveSnapshotAt = nil
            }
        }

        liveSnapshot?.apply(to: &data)
    }

    private func fetchLiveCLIUsage(_ data: inout ClaudeUsageData) {
        guard !claudeBinaryPath.isEmpty else { return }

        let homeDir = NSHomeDirectory()
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.runwayleft.app", isDirectory: true)
            .appendingPathComponent("cli_workdir", isDirectory: true)

        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: claudeBinaryPath)
        task.arguments = [
            "-p", "/usage",
            "--output-format", "json",
            "--tools", "",
            "--no-session-persistence"
        ]

        task.currentDirectoryURL = workDirectory

        // Clean environment: avoid setting SHELL to prevent loading login shell configs (.zprofile, .zshrc)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:\(homeDir)/.local/bin"
        env["HOME"] = homeDir
        env["USER"] = NSUserName()
        env["TERM"] = "dumb"
        env["CI"] = "1"
        env["NO_COLOR"] = "1"
        env.removeValue(forKey: "SHELL")
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
            let deadline = Date().addingTimeInterval(15)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if task.isRunning {
                task.terminate()
                task.waitUntilExit()
                return
            }
            let rawData = pipe.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0 else { return }

            guard let output = String(data: rawData, encoding: .utf8) else { return }

            if let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let result = json["result"] as? String {
                parseUsageText(result, into: &data)
            } else {
                parseUsageText(output, into: &data)
            }
        } catch { return }
    }

    private func parseUsageText(_ text: String, into data: inout ClaudeUsageData) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Current session:") {
                if let pct = extractPercentage(trimmed) {
                    data.sessionUsedPct = pct
                    data.hasLiveStatus = true
                }
                if let resets = extractResetText(trimmed) {
                    data.sessionReset = resets
                }
            } else if trimmed.contains("Current week (all models):") {
                if let pct = extractPercentage(trimmed) {
                    data.weekAllModelsPct = pct
                    data.hasLiveStatus = true
                }
                if let resets = extractResetText(trimmed) {
                    data.weekAllModelsReset = resets
                }
            } else if trimmed.contains("Current week (Fable):") || trimmed.contains("Current week (") {
                if let pct = extractPercentage(trimmed) {
                    data.weekFablePct = pct
                    data.hasLiveStatus = true
                }
                if let open = trimmed.range(of: "Current week ("),
                   let close = trimmed[open.upperBound...].firstIndex(of: ")") {
                    data.weekModelLabel = String(trimmed[open.upperBound..<close])
                }
                if let resets = extractResetText(trimmed) {
                    data.weekFableReset = resets
                }
            }
        }
    }

    private func extractPercentage(_ str: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)%"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
           let range = Range(match.range(at: 1), in: str) {
            return Double(str[range])
        }
        return nil
    }

    private func extractResetText(_ str: String) -> String? {
        if let resetRange = str.range(of: "resets ") {
            return String(str[resetRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
