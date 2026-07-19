import Foundation

class ClaudeDataReader {
    static let shared = ClaudeDataReader()
    
    private let statsFilePath: String
    private let claudeBinaryPath: String
    
    init(customPath: String? = nil) {
        if let path = customPath {
            self.statsFilePath = path
        } else {
            self.statsFilePath = NSString(string: "~/.claude/stats-cache.json").expandingTildeInPath
        }
        
        let candidates = [
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        self.claudeBinaryPath = candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? ""
    }
    
    func fetchUsageData() -> ClaudeUsageData {
        var data = ClaudeUsageData()
        let fileURL = URL(fileURLWithPath: statsFilePath)
        
        // 1. Read JSON stats-cache.json for historical daily tokens and messages
        if FileManager.default.fileExists(atPath: statsFilePath),
           let jsonData = try? Data(contentsOf: fileURL),
           let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            
            data.lastComputedDate = root["lastComputedDate"] as? String ?? ""
            data.totalSessions = root["totalSessions"] as? Int ?? 0
            data.totalMessages = root["totalMessages"] as? Int ?? 0
            
            // Parse dailyActivity
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
            
            // Parse dailyModelTokens
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
            
            // Parse modelUsage
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
        
        // 2. Compute today's tokens and activity live from session
        // transcripts, since stats-cache.json is only refreshed
        // periodically and can lag behind by up to a full day.
        mergeTodayLiveStatsFromTranscripts(&data)

        // 3. Execute claude -p /usage CLI command for live subscription status
        fetchLiveCLIUsage(&data)

        return data
    }

    private func mergeTodayLiveStatsFromTranscripts(_ data: inout ClaudeUsageData) {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let projectsDir = NSString(string: "~/.claude/projects").expandingTildeInPath
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

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
            // Skip files untouched today, so we only parse transcripts
            // that could actually contain today's activity.
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

                // Streaming/tool-use turns log the same message id multiple
                // times with an identical cumulative usage snapshot; count
                // each message id once to avoid inflating the token total.
                let messageID = message["id"] as? String ?? UUID().uuidString
                guard seenMessageIDs.insert(messageID).inserted else { continue }

                let input = (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0
                let output = (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? NSNumber)?.int64Value ?? 0

                // Deliberately excludes cache_read_input_tokens: cache reads
                // recur on nearly every turn as the accumulated context is
                // replayed, so including them inflates the daily total by
                // 30-60x versus what stats-cache.json's dailyModelTokens
                // reports for past days and makes today's number
                // incomparable to the rest of the chart.
                tokenTotals[model, default: 0] += input + output + cacheCreate
            }
        }

        guard messageCount > 0 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)

        if !tokenTotals.isEmpty {
            data.dailyModelTokens.removeAll { $0.date == todayStr }
            data.dailyModelTokens.append(ClaudeDailyModelTokens(date: todayStr, tokensByModel: tokenTotals))
        }

        data.dailyActivity.removeAll { $0.date == todayStr }
        data.dailyActivity.append(ClaudeDailyActivity(
            date: todayStr,
            messageCount: messageCount,
            sessionCount: sessionIDs.count,
            toolCallCount: toolCallCount
        ))
    }
    
    private func fetchLiveCLIUsage(_ data: inout ClaudeUsageData) {
        guard !claudeBinaryPath.isEmpty else { return }
        
        let homeDir = NSHomeDirectory()
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.aiusagetracker.app", isDirectory: true)
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
                return
            }
            let rawData = pipe.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0 else { return }
            
            guard let output = String(data: rawData, encoding: .utf8) else { return }
            
            // Try JSON output first (from --output-format json)
            if let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let result = json["result"] as? String {
                parseUsageText(result, into: &data)
            } else {
                // Fallback: parse raw text output
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
