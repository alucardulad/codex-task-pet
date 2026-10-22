import Darwin
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CodexDataVersion: Equatable {
    fileprivate let values: [Int64]
}

final class CodexDatabase {
    enum DatabaseError: LocalizedError {
        case openFailed(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message): return "无法打开 Codex 数据库：\(message)"
            case .queryFailed(let message): return "读取 Codex 任务失败：\(message)"
            }
        }
    }

    private var db: OpaquePointer?
    private let watchedPaths: [String]

    init() throws {
        let statePath = NSString(string: "~/.codex/state_5.sqlite").expandingTildeInPath
        let historyPath = NSString(string: "~/.codex/thread_history_1.sqlite").expandingTildeInPath
        self.watchedPaths = [
            statePath,
            statePath + "-wal",
            historyPath,
            historyPath + "-wal"
        ]

        guard FileManager.default.fileExists(atPath: statePath),
              FileManager.default.fileExists(atPath: historyPath) else {
            throw DatabaseError.openFailed("找不到本机 Codex 数据文件")
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(statePath, &db, flags, nil) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if db != nil { sqlite3_close(db) }
            db = nil
            throw DatabaseError.openFailed(message)
        }

        sqlite3_busy_timeout(db, 500)
        let escapedHistory = historyPath.replacingOccurrences(of: "'", with: "''")
        let attach = "ATTACH DATABASE '\(escapedHistory)' AS hist"
        let configure = """
        PRAGMA cache_size = -512;
        PRAGMA hist.cache_size = -512;
        PRAGMA temp_store = FILE;
        PRAGMA query_only = ON;
        """
        if sqlite3_exec(db, attach, nil, nil, nil) != SQLITE_OK
            || sqlite3_exec(db, configure, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw DatabaseError.openFailed(message)
        }
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    /// A cheap filesystem fingerprint lets the polling timer skip an expensive query
    /// when Codex has not written any new task data.
    func dataVersion() -> CodexDataVersion {
        var values: [Int64] = []
        values.reserveCapacity(watchedPaths.count * 3)

        for path in watchedPaths {
            var info = stat()
            let succeeded = path.withCString { stat($0, &info) == 0 }
            if succeeded {
                values.append(Int64(info.st_mtimespec.tv_sec))
                values.append(Int64(info.st_mtimespec.tv_nsec))
                values.append(Int64(info.st_size))
            } else {
                values.append(contentsOf: [-1, -1, -1])
            }
        }
        return CodexDataVersion(values: values)
    }

    func fetchTasks(now: Date = Date()) throws -> [AgentTask] {
        let activeCutoff = Int(now.addingTimeInterval(-30 * 60).timeIntervalSince1970) * 1000
        let recentCutoff = Int(now.addingTimeInterval(-6 * 60 * 60).timeIntervalSince1970)
        let recentCutoffMS = recentCutoff * 1000

        let sql = """
        SELECT
            t.id,
            COALESCE(NULLIF(t.name, ''), NULLIF(t.title, ''), NULLIF(t.first_user_message, ''), '未命名任务') AS title,
            COALESCE(t.cwd, '') AS cwd,
            COALESCE(t.source, '') AS source,
            COALESCE(t.thread_source, '') AS thread_source,
            COALESCE(t.originator, '') AS originator,
            COALESCE(t.updated_at_ms, 0) AS updated_at_ms,
            COALESCE(rt.turn_id, '') AS turn_id,
            COALESCE(rt.status, '') AS turn_status,
            rt.started_at,
            rt.completed_at,
            COALESCE(ri.item_type, '') AS item_type,
            COALESCE(ri.item_json, '{}') AS item_json,
            MAX(
                COALESCE(ri.created_at_ms, 0),
                COALESCE(t.updated_at_ms, 0),
                COALESCE(rt.started_at * 1000, 0)
            ) AS activity_ms
        FROM threads t
        JOIN hist.thread_turns rt
          ON rt.thread_id = t.id
         AND rt.rowid = (
             SELECT latest_turn.rowid
             FROM hist.thread_turns latest_turn
             WHERE latest_turn.thread_id = t.id
             ORDER BY latest_turn.started_at DESC, latest_turn.rowid DESC
             LIMIT 1
         )
        LEFT JOIN hist.thread_items ri
          ON ri.thread_id = rt.thread_id
         AND ri.turn_id = rt.turn_id
         AND ri.rowid = (
             SELECT latest_item.rowid
             FROM hist.thread_items latest_item
             WHERE latest_item.thread_id = rt.thread_id
               AND latest_item.turn_id = rt.turn_id
             ORDER BY latest_item.created_at_ms DESC, latest_item.rollout_ordinal DESC
             LIMIT 1
         )
        WHERE t.archived = 0
          AND t.updated_at_ms >= ?
          AND (
              (rt.status = 'inProgress' AND MAX(
                  COALESCE(ri.created_at_ms, 0),
                  COALESCE(t.updated_at_ms, 0),
                  COALESCE(rt.started_at * 1000, 0)
              ) >= ?)
              OR
              (rt.status IN ('completed', 'failed', 'interrupted') AND COALESCE(rt.completed_at, 0) >= ?)
          )
        ORDER BY
            CASE rt.status WHEN 'inProgress' THEN 0 WHEN 'failed' THEN 1 WHEN 'interrupted' THEN 2 ELSE 3 END,
            activity_ms DESC
        LIMIT 16
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(recentCutoffMS))
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(activeCutoff))
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(recentCutoff))

        var tasks: [AgentTask] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = text(stmt, 0)
            let title = shorten(text(stmt, 1), limit: 70)
            let cwd = text(stmt, 2)
            let source = text(stmt, 3)
            let threadSource = text(stmt, 4)
            let originator = text(stmt, 5)
            let status = AgentStatus(rawValue: text(stmt, 8)) ?? .completed
            let itemType = text(stmt, 11)
            let itemJSON = text(stmt, 12)

            let startedAt = optionalDate(seconds: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 9))
            let completedAt = optionalDate(seconds: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 10))
            let activityMS = sqlite3_column_int64(stmt, 13)
            let activity = Date(timeIntervalSince1970: TimeInterval(activityMS) / 1000.0)
            let projectName = projectName(from: cwd)
            let isSubagent = isSubagent(source: source, threadSource: threadSource, originator: originator)

            tasks.append(AgentTask(
                id: id,
                title: title.isEmpty ? "未命名任务" : title,
                projectName: projectName,
                status: status,
                currentAction: actionLabel(itemType: itemType, itemJSON: itemJSON, status: status),
                preview: previewText(itemType: itemType, itemJSON: itemJSON),
                startedAt: startedAt,
                completedAt: completedAt,
                latestActivity: activity,
                isSubagent: isSubagent
            ))
        }

        return tasks
    }

    func fetchCompletions(since: Date, through: Date) throws -> [CompletionEvent] {
        let sql = """
        SELECT
            t.id,
            COALESCE(NULLIF(t.name, ''), NULLIF(t.title, ''), NULLIF(t.first_user_message, ''), '未命名任务') AS title,
            COALESCE(t.cwd, '') AS cwd,
            COALESCE(t.source, '') AS source,
            COALESCE(t.thread_source, '') AS thread_source,
            COALESCE(t.originator, '') AS originator,
            tt.turn_id,
            tt.status,
            tt.completed_at,
            COALESCE((
                SELECT final_item.item_json
                FROM hist.thread_items final_item
                WHERE final_item.thread_id = tt.thread_id
                  AND final_item.turn_id = tt.turn_id
                  AND final_item.item_type = 'agentMessage'
                ORDER BY final_item.created_at_ms DESC, final_item.rollout_ordinal DESC
                LIMIT 1
            ), '{}') AS final_json
        FROM hist.thread_turns tt
        JOIN threads t ON t.id = tt.thread_id
        WHERE t.archived = 0
          AND tt.status IN ('completed', 'failed', 'interrupted')
          AND tt.completed_at IS NOT NULL
          AND tt.completed_at >= ?
          AND tt.completed_at <= ?
        ORDER BY tt.completed_at ASC
        LIMIT 30
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(since.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(through.timeIntervalSince1970))

        var events: [CompletionEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let taskID = text(stmt, 0)
            let title = shorten(text(stmt, 1), limit: 70)
            let cwd = text(stmt, 2)
            let source = text(stmt, 3)
            let threadSource = text(stmt, 4)
            let originator = text(stmt, 5)
            let turnID = text(stmt, 6)
            let status = AgentStatus(rawValue: text(stmt, 7)) ?? .completed
            let completedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 8)))
            let finalText = messageText(from: text(stmt, 9))

            let message: String
            switch status {
            case .failed: message = finalText.isEmpty ? "这次执行遇到了问题，打开任务看看详情。" : finalText
            case .interrupted: message = finalText.isEmpty ? "任务已中断。" : finalText
            default: message = finalText.isEmpty ? "这一轮已经处理完毕。" : finalText
            }

            events.append(CompletionEvent(
                id: turnID,
                taskID: taskID,
                title: title.isEmpty ? "未命名任务" : title,
                projectName: projectName(from: cwd),
                status: status,
                message: shorten(message, limit: 130),
                completedAt: completedAt,
                isSubagent: isSubagent(source: source, threadSource: threadSource, originator: originator)
            ))
        }
        return events
    }

    func debugSnapshot() throws {
        let tasks = try fetchTasks()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tasks)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let db else { throw DatabaseError.queryFailed("数据库连接已关闭") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func optionalDate(seconds: Int64?) -> Date? {
        guard let seconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func projectName(from cwd: String) -> String {
        guard !cwd.isEmpty else { return "Codex" }
        let url = URL(fileURLWithPath: cwd)
        let last = url.lastPathComponent
        if last == "w", cwd.contains("/Documents/Codex/") {
            return "Codex"
        }
        return last.isEmpty ? "Codex" : last
    }

    private func isSubagent(source: String, threadSource: String, originator: String) -> Bool {
        let combined = "\(source) \(threadSource) \(originator)".lowercased()
        return combined.contains("subagent") || combined.contains("guardian_review")
    }

    private func actionLabel(itemType: String, itemJSON: String, status: AgentStatus) -> String {
        if status == .completed { return "已完成" }
        if status == .failed { return "遇到错误" }
        if status == .interrupted { return "已中断" }

        switch itemType {
        case "reasoning": return "思考中"
        case "commandExecution": return "执行命令"
        case "mcpToolCall": return "调用工具"
        case "webSearch": return "搜索资料"
        case "fileChange": return "修改文件"
        case "agentMessage": return "整理进展"
        case "imageView": return "查看图片"
        default: return "处理中"
        }
    }

    private func previewText(itemType: String, itemJSON: String) -> String {
        guard let data = itemJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let text = object["text"] as? String, !text.isEmpty {
            return shorten(text.replacingOccurrences(of: "\n", with: " "), limit: 110)
        }
        if let command = object["command"] as? String, !command.isEmpty {
            return shorten(command.replacingOccurrences(of: "\n", with: " "), limit: 110)
        }
        if let query = object["query"] as? String, !query.isEmpty {
            return shorten(query, limit: 110)
        }
        return ""
    }

    private func messageText(from itemJSON: String) -> String {
        guard let data = itemJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            return ""
        }
        return text
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shorten(_ value: String, limit: Int) -> String {
        let compact = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit - 1)) + "…"
    }
}
