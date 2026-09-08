import Foundation
import SQLite3

class CodexDataReader {
    static let shared = CodexDataReader()

    /// Spawning `codex app-server` is cheap compared to the Claude CLI but still
    /// a process per call, so it runs at most this often unless forced.
    static let liveStatusInterval: TimeInterval = 300
    static let liveStatusMaxAge: TimeInterval = 1800

    /// Codex reports a short window (5 hours) and a long one (7 days).
    enum RateLimitWindow {
        case session
        case weekly
        case unknown
    }

    static func classifyWindow(minutes: Int?) -> RateLimitWindow {
        guard let minutes = minutes, minutes > 0 else { return .unknown }
        return minutes >= 10_080 ? .weekly : .session
    }

    private let sqlitePath: String
    private let authFilePath: String
    private let configFilePath: String
    private let sessionsDirectoryPath: String

    private var liveSnapshot: LiveSnapshot?
    private var liveSnapshotAt: Date?
    private var liveAttemptedAt: Date?

    struct LiveSnapshot {
        var accountPlan: String
        var sessionLimitUsedPct: Double?
        var sessionLimitResetText: String
        var weeklyLimitUsedPct: Double?
        var weeklyLimitResetText: String
        var resets: [CodexResetItem]
        var availableResetCreditsCount: Int?

        init(from data: CodexUsageData) {
            accountPlan = data.accountPlan
            sessionLimitUsedPct = data.sessionLimitUsedPct
            sessionLimitResetText = data.sessionLimitResetText
            weeklyLimitUsedPct = data.weeklyLimitUsedPct
            weeklyLimitResetText = data.weeklyLimitResetText
            resets = data.resets
            availableResetCreditsCount = data.availableResetCreditsCount
        }

        func apply(to data: inout CodexUsageData) {
            if !accountPlan.isEmpty { data.accountPlan = accountPlan }
            data.sessionLimitUsedPct = sessionLimitUsedPct
            data.sessionLimitResetText = sessionLimitResetText
            data.weeklyLimitUsedPct = weeklyLimitUsedPct
            data.weeklyLimitResetText = weeklyLimitResetText
            data.resets = resets
            data.availableResetCreditsCount = availableResetCreditsCount
        }
    }

    init(customPath: String? = nil) {
        if let path = customPath {
            self.sqlitePath = path
            self.authFilePath = (path as NSString).deletingLastPathComponent + "/auth.json"
            self.configFilePath = (path as NSString).deletingLastPathComponent + "/config.toml"
            self.sessionsDirectoryPath = (path as NSString).deletingLastPathComponent + "/sessions"
        } else {
            self.sqlitePath = NSString(string: "~/.codex/state_5.sqlite").expandingTildeInPath
            self.authFilePath = NSString(string: "~/.codex/auth.json").expandingTildeInPath
            self.configFilePath = NSString(string: "~/.codex/config.toml").expandingTildeInPath
            self.sessionsDirectoryPath = NSString(string: "~/.codex/sessions").expandingTildeInPath
        }
    }

    /// - Parameter forceLive: query the app-server even if the cached limits
    ///   are still fresh (the Refresh button passes true).
    func fetchUsageData(forceLive: Bool = false) -> CodexUsageData {
        var data = CodexUsageData()

        // 1. Read Auth & Account Info from auth.json
        if FileManager.default.fileExists(atPath: authFilePath),
           let authData = try? Data(contentsOf: URL(fileURLWithPath: authFilePath)),
           let authRoot = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
           let idTokenStr = authRoot["tokens"] as? [String: Any],
           let idToken = idTokenStr["id_token"] as? String {

            let parts = idToken.components(separatedBy: ".")
            if parts.count >= 2,
               let payloadData = base64UrlDecode(parts[1]),
               let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                if let email = payload["email"] as? String {
                    data.accountEmail = email
                }
                if let authObj = payload["https://api.openai.com/auth"] as? [String: Any],
                   let plan = authObj["chatgpt_plan_type"] as? String {
                    data.accountPlan = plan.capitalized
                }
            }
        }

        // 2. Read Configured Model from config.toml
        if FileManager.default.fileExists(atPath: configFilePath),
           let configText = try? String(contentsOfFile: configFilePath, encoding: .utf8) {
            let lines = configText.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let m = parts[1].trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if !m.isEmpty {
                            data.activeModel = m
                        }
                    }
                }
            }
        }

        // 3. Live rate limits, throttled; session logs as the fallback.
        applyLiveStatus(&data, force: forceLive)

        // 4. Read SQLite Database state_5.sqlite
        readDatabase(into: &data)

        return data
    }

    private func applyLiveStatus(_ data: inout CodexUsageData, force: Bool) {
        let now = Date()
        let attemptIsFresh = liveAttemptedAt.map { now.timeIntervalSince($0) < Self.liveStatusInterval } ?? false

        if force || !attemptIsFresh {
            var probe = CodexUsageData()
            let live = applyLiveAccountStatus(to: &probe)
            liveAttemptedAt = now

            if live {
                liveSnapshot = LiveSnapshot(from: probe)
                liveSnapshotAt = now
            } else if let takenAt = liveSnapshotAt, now.timeIntervalSince(takenAt) > Self.liveStatusMaxAge {
                liveSnapshot = nil
                liveSnapshotAt = nil
            }
        }

        if let snapshot = liveSnapshot {
            snapshot.apply(to: &data)
        }
        // Whatever the app-server did not report comes from the session logs.
        // Live values are never overwritten.
        if data.sessionLimitUsedPct == nil || data.weeklyLimitUsedPct == nil {
            fillRateLimitsFromSessionLogs(into: &data, now: now)
        }
    }

    /// Reads the local `threads` table. Split out so it can be exercised
    /// against a temporary database without spawning the Codex app-server.
    func readDatabase(into data: inout CodexUsageData) {
        guard FileManager.default.fileExists(atPath: sqlitePath) else {
            return
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(
            sqlitePath,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let db = db else {
            if let db = db { sqlite3_close(db) }
            return
        }

        defer {
            sqlite3_close(db)
        }

        // Daily Usage
        let dailyQuery = """
            SELECT date(created_at, 'unixepoch', 'localtime') as day,
                   COUNT(*) as session_count,
                   SUM(tokens_used) as total_tokens
            FROM threads
            GROUP BY day
            ORDER BY day DESC;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, dailyQuery, -1, &stmt, nil) == SQLITE_OK {
            var list: [CodexDailyUsage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let dayCStr = sqlite3_column_text(stmt, 0) {
                    let day = String(cString: dayCStr)
                    let count = Int(sqlite3_column_int(stmt, 1))
                    let tokens = sqlite3_column_int64(stmt, 2)
                    list.append(CodexDailyUsage(date: day, sessionCount: count, tokensUsed: tokens))
                }
            }
            data.dailyUsage = list
            sqlite3_finalize(stmt)
        }

        // Total Sessions & Tokens
        let totalQuery = "SELECT COUNT(*), SUM(tokens_used) FROM threads;"
        if sqlite3_prepare_v2(db, totalQuery, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                data.totalSessions = Int(sqlite3_column_int(stmt, 0))
                data.totalTokens = sqlite3_column_int64(stmt, 1)
            }
            sqlite3_finalize(stmt)
        }

        // 1-Week Window Tokens
        let sevenDaysAgoInt = Int64(Date().timeIntervalSince1970 - (7 * 86400))
        let query7d = """
            SELECT SUM(tokens_used), COUNT(*)
            FROM threads
            WHERE created_at >= \(sevenDaysAgoInt);
        """
        if sqlite3_prepare_v2(db, query7d, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                data.tokensIn1WeekWindow = sqlite3_column_int64(stmt, 0)
                data.sessionsIn1WeekWindow = Int(sqlite3_column_int(stmt, 1))
            }
            sqlite3_finalize(stmt)
        }

        // Model Breakdown
        let modelQuery = """
            SELECT COALESCE(NULLIF(model, ''), 'unknown') as model_name,
                   COUNT(*) as session_count,
                   SUM(tokens_used) as total_tokens
            FROM threads
            GROUP BY model_name
            ORDER BY total_tokens DESC;
        """
        if sqlite3_prepare_v2(db, modelQuery, -1, &stmt, nil) == SQLITE_OK {
            var models: [CodexModelUsage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: nameCStr)
                    let count = Int(sqlite3_column_int(stmt, 1))
                    let tokens = sqlite3_column_int64(stmt, 2)
                    models.append(CodexModelUsage(modelName: name, sessionCount: count, totalTokens: tokens))
                }
            }
            data.modelBreakdown = models
            sqlite3_finalize(stmt)
        }

        // Per-day, per-model buckets for the Models tab time selector.
        let dailyModelQuery = """
            SELECT date(created_at, 'unixepoch', 'localtime') as day,
                   COALESCE(NULLIF(model, ''), 'unknown') as model_name,
                   COUNT(*) as session_count,
                   SUM(tokens_used) as total_tokens
            FROM threads
            GROUP BY day, model_name
            ORDER BY day DESC, total_tokens DESC;
        """
        if sqlite3_prepare_v2(db, dailyModelQuery, -1, &stmt, nil) == SQLITE_OK {
            var buckets: [CodexDailyModelTokens] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let dayCStr = sqlite3_column_text(stmt, 0), let nameCStr = sqlite3_column_text(stmt, 1) {
                    buckets.append(CodexDailyModelTokens(
                        date: String(cString: dayCStr),
                        modelName: String(cString: nameCStr),
                        sessionCount: Int(sqlite3_column_int(stmt, 2)),
                        tokens: sqlite3_column_int64(stmt, 3)
                    ))
                }
            }
            data.dailyModelTokens = buckets
            sqlite3_finalize(stmt)
        }
    }

    /// A session log last written longer ago than a window lasts cannot hold an
    /// unexpired snapshot of that window, so such files are not opened at all.
    private static let weeklyWindowSeconds: TimeInterval = 7 * 24 * 3600
    private static let sessionWindowSeconds: TimeInterval = 5 * 3600

    /// Fills whichever windows are still empty from the newest session-log
    /// snapshot that has them. Slots already holding a value are kept, so live
    /// data always wins. A window whose reset time has passed is skipped: the
    /// snapshot then says nothing about the current window, and showing it would
    /// pair a stale percentage with a reset date in the past.
    func fillRateLimitsFromSessionLogs(into data: inout CodexUsageData, now: Date = Date()) {
        guard data.sessionLimitUsedPct == nil || data.weeklyLimitUsedPct == nil else { return }
        let maxAge = data.weeklyLimitUsedPct == nil ? Self.weeklyWindowSeconds : Self.sessionWindowSeconds
        let cutoff = now.addingTimeInterval(-maxAge)

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: sessionsDirectoryPath),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let files = enumerator.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff else { return nil }
            return (url, modified)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(20)

        let sessionCutoff = now.addingTimeInterval(-Self.sessionWindowSeconds)
        for (url, modified) in files {
            // Newest first, so once only the 5-hour slot is left, a file older
            // than five hours ends the scan rather than being read for nothing.
            if data.weeklyLimitUsedPct != nil, modified < sessionCutoff { break }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n").reversed() {
                guard let lineData = line.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let payload = root["payload"] as? [String: Any],
                      let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }

                Self.applyRateLimits(rateLimits, to: &data, onlyIfMissing: true, expiredBefore: now)
                if data.sessionLimitUsedPct != nil && data.weeklyLimitUsedPct != nil { return }
            }
        }
    }

    private func applyLiveAccountStatus(to data: inout CodexUsageData) -> Bool {
        guard let codexBinary = findCodexBinary() else { return false }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: codexBinary)
        task.arguments = ["app-server", "--stdio"]
        task.currentDirectoryURL = FileManager.default.temporaryDirectory
        task.standardError = FileHandle.nullDevice

        let homeDir = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        let codexBinDir = (codexBinary as NSString).deletingLastPathComponent
        var pathComponents = [
            codexBinDir,
            "\(homeDir)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let nvmRoot = "\(homeDir)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            pathComponents.append(contentsOf: versions.map { "\(nvmRoot)/\($0)/bin" })
        }
        env["PATH"] = pathComponents.joined(separator: ":")
        env["HOME"] = homeDir
        env["USER"] = NSUserName()
        task.environment = env

        let input = Pipe()
        let output = Pipe()
        task.standardInput = input
        task.standardOutput = output

        do {
            try task.run()
            let responseReady = DispatchSemaphore(value: 0)
            let responseLock = NSLock()
            var responseData = Data()
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                responseLock.lock()
                responseData.append(chunk)
                let hasResponse = responseData.range(of: Data(#""id":2"#.utf8)) != nil
                responseLock.unlock()
                if hasResponse { responseReady.signal() }
            }

            let requests = [
                #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"runwayleft","title":"RunwayLeft","version":"1.0.0"}}}"#,
                #"{"method":"initialized","params":{}}"#,
                #"{"method":"account/rateLimits/read","id":2,"params":{}}"#
            ].joined(separator: "\n") + "\n"
            input.fileHandleForWriting.write(Data(requests.utf8))

            _ = responseReady.wait(timeout: .now() + 30)
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if task.isRunning {
                task.terminate()
                task.waitUntilExit()
            }

            responseLock.lock()
            let capturedData = responseData
            responseLock.unlock()
            guard let responseText = String(data: capturedData, encoding: .utf8) else { return false }

            for line in responseText.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      (root["id"] as? NSNumber)?.intValue == 2,
                      let result = root["result"] as? [String: Any] else { continue }

                let limits: [String: Any]?
                if let rateLimits = result["rateLimits"] as? [String: Any] {
                    limits = rateLimits
                } else if let byId = result["rateLimitsByLimitId"] as? [String: Any],
                          let codexLimits = byId["codex"] as? [String: Any] {
                    limits = codexLimits
                } else {
                    limits = nil
                }

                if let limits = limits {
                    Self.applyRateLimits(limits, to: &data)
                }

                applyResetCredits(result["rateLimitResetCredits"], to: &data)
                return data.weeklyLimitUsedPct != nil || data.sessionLimitUsedPct != nil || data.availableResetCreditsCount != nil
            }
        } catch {
            if task.isRunning {
                task.terminate()
                task.waitUntilExit()
            }
        }
        return false
    }

    /// Applies the `primary` and `secondary` windows of a rate-limit object in
    /// either spelling: the app-server's camelCase (`usedPercent`,
    /// `windowDurationMins`, `resetsAt`) or the session logs' snake_case
    /// (`used_percent`, `window_minutes`, `resets_at`).
    ///
    /// - Parameters:
    ///   - onlyIfMissing: keep slots that already hold a value.
    ///   - expiredBefore: skip a window whose reset time is earlier than this.
    static func applyRateLimits(
        _ limits: [String: Any],
        to data: inout CodexUsageData,
        onlyIfMissing: Bool = false,
        expiredBefore: Date? = nil
    ) {
        for (key, slot) in [("primary", RateLimitWindow.session), ("secondary", .weekly)] {
            guard let window = limits[key] as? [String: Any],
                  let used = number(in: window, "usedPercent", "used_percent")?.doubleValue else { continue }
            let resetsAt = number(in: window, "resetsAt", "resets_at")?.doubleValue
            let minutes = number(in: window, "windowDurationMins", "window_minutes")?.intValue
            if let expiredBefore, let resetsAt, Date(timeIntervalSince1970: resetsAt) < expiredBefore { continue }
            applyRateLimitWindow(
                usedPercent: used,
                resetsAt: resetsAt,
                minutes: minutes,
                positionalSlot: slot,
                to: &data,
                onlyIfMissing: onlyIfMissing
            )
        }
        if let planType = limits["planType"] as? String, !planType.isEmpty {
            data.accountPlan = planType.capitalized
        }
    }

    private static func number(in window: [String: Any], _ camelCase: String, _ snakeCase: String) -> NSNumber? {
        (window[camelCase] as? NSNumber) ?? (window[snakeCase] as? NSNumber)
    }

    /// Routes one window to the session or weekly slot by its duration. The
    /// duration always wins: session logs have carried the weekly window alone
    /// under `primary`. Only without one does the slot follow the key, `primary`
    /// as the 5-hour window and `secondary` as the weekly one, which is how the
    /// app-server orders them.
    static func applyRateLimitWindow(
        usedPercent: Double,
        resetsAt: Double?,
        minutes: Int?,
        positionalSlot: RateLimitWindow,
        to data: inout CodexUsageData,
        onlyIfMissing: Bool = false
    ) {
        let used = max(0, min(100, usedPercent))
        let resetText = resetsAt.map { "resets \(formatResetDate(Date(timeIntervalSince1970: $0)))" } ?? ""

        var window = classifyWindow(minutes: minutes)
        if window == .unknown {
            window = positionalSlot
        }

        switch window {
        case .weekly:
            guard !onlyIfMissing || data.weeklyLimitUsedPct == nil else { return }
            data.weeklyLimitUsedPct = used
            data.weeklyLimitResetText = resetText
        case .session:
            guard !onlyIfMissing || data.sessionLimitUsedPct == nil else { return }
            data.sessionLimitUsedPct = used
            data.sessionLimitResetText = resetText
        case .unknown:
            break
        }
    }

    func applyResetCredits(_ value: Any?, to data: inout CodexUsageData) {
        guard let summary = value as? [String: Any] else { return }
        data.availableResetCreditsCount = (summary["availableCount"] as? NSNumber)?.intValue
        guard let credits = summary["credits"] as? [[String: Any]] else { return }

        let availableCredits = credits.filter { credit in
            guard let status = credit["status"] as? String else { return false }
            return status.lowercased() == "available"
        }

        data.resets = availableCredits.enumerated().map { index, credit in
            let title = (credit["title"] as? String) ?? "Full reset"
            let expiry: String
            if let timestamp = (credit["expiresAt"] as? NSNumber)?.doubleValue {
                expiry = Self.formatResetDate(Date(timeIntervalSince1970: timestamp))
            } else {
                expiry = "No expiry"
            }
            return CodexResetItem(index: index + 1, name: title, expiryText: expiry)
        }
    }

    private func findCodexBinary() -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            candidates.append(contentsOf: versions.sorted().reversed().map {
                "\(nvmRoot)/\($0)/bin/codex"
            })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter
    }()

    private static func formatResetDate(_ date: Date) -> String {
        resetDateFormatter.string(from: date)
    }

    private func base64UrlDecode(_ base64Url: String) -> Data? {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}
