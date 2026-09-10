import AppKit
import Foundation
import SQLite3

@MainActor
final class TeamsNudgeProvider: NudgeProvider {
    let source: NudgeSource = .teams

    private var cache: [Nudge] = []
    private var lastQuery = Date.distantPast
    private let cacheTTL: TimeInterval = 20

    private var stubURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DynamicIsland/teams-nudge-stub.json")
    }

    func currentNudges() async -> [Nudge] {
        let now = Date()
        if now.timeIntervalSince(lastQuery) < cacheTTL {
            return cache
        }
        lastQuery = now
        // Chromium logs are skipped: they retain historical chat text and cannot prove unread.
        cache = loadStub(now: now)
            ?? loadNotificationCenter(now: now)
            ?? loadDockBadge(now: now)
            ?? []
        return cache
    }

    // MARK: - Stub

    private func loadStub(now: Date) -> [Nudge]? {
        guard FileManager.default.fileExists(atPath: stubURL.path),
              let data = try? Data(contentsOf: stubURL),
              let rows = try? JSONDecoder().decode([TeamsStubRow].self, from: data)
        else { return nil }

        let unreadRows = rows.filter { $0.unread == true }
        guard !unreadRows.isEmpty else { return nil }

        return unreadRows.prefix(3).map { row in
            let mentioned = row.mentioned == true || Self.looksLikeMention(row.body)
            return Nudge(
                id: "teams.stub.\(row.sender).\(row.body.hashValue)",
                source: .teams,
                emoji: "",
                title: row.sender,
                description: Self.snippet(row.body),
                priority: mentioned ? .urgent : .high,
                createdAt: now
            )
        }
    }

    // MARK: - Notification Center (local SQLite, no network)

    private func loadNotificationCenter(now: Date) -> [Nudge]? {
        guard let dbURL = notificationCenterDBURL() else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("di-nc-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            if FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.removeItem(at: tmp)
            }
            try FileManager.default.copyItem(at: dbURL, to: tmp)
        } catch {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        // Unpresented + recent: historical delivered banners are not unread proof.
        let sql = """
        SELECT rec.data
        FROM record rec
        JOIN app ON app.app_id = rec.app_id
        WHERE app.identifier LIKE '%teams%'
          AND rec.presented = 0
          AND rec.delivered_date > ?
        ORDER BY rec.delivered_date DESC
        LIMIT 8;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let recentCutoff = Date().addingTimeInterval(-4 * 3600).timeIntervalSinceReferenceDate
        sqlite3_bind_double(statement, 1, recentCutoff)

        var nudges: [Nudge] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(statement, 0) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: blob, count: length)
            guard let parsed = Self.parseNotificationPayload(data) else { continue }
            let mentioned = Self.looksLikeMention(parsed.body)
            nudges.append(
                Nudge(
                    id: "teams.nc.\(parsed.title).\(parsed.body.hashValue)",
                    source: .teams,
                    emoji: "",
                    title: parsed.title,
                    description: Self.snippet(parsed.body),
                    priority: mentioned ? .urgent : .high,
                    createdAt: now
                )
            )
        }
        return nudges.isEmpty ? nil : nudges
    }

    private func notificationCenterDBURL() -> URL? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count)
        guard n > 0 else { return nil }
        let dir = String(cString: buffer)
        let url = URL(fileURLWithPath: dir)
            .appendingPathComponent("com.apple.notificationcenter/db2/db")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Dock badge (count only)

    private func loadDockBadge(now: Date) -> [Nudge]? {
        let names = ["Microsoft Teams", "Microsoft Teams (work or school)", "Teams"]
        for name in names {
            let script = """
            tell application "System Events"
              if exists UI element "\(name)" of list 1 of process "Dock" then
                return value of attribute "AXStatusLabel" of UI element "\(name)" of list 1 of process "Dock"
              end if
            end tell
            """
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            let result = appleScript?.executeAndReturnError(&error)
            let label = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let count = Int(label), count > 0 else { continue }
            return [
                Nudge(
                    id: "teams.dock.\(count)",
                    source: .teams,
                    emoji: "",
                    title: "Microsoft Teams",
                    description: count == 1 ? "1 mensagem não lida" : "\(count) mensagens não lidas",
                    priority: .high,
                    createdAt: now
                )
            ]
        }
        return nil
    }

    // MARK: - Parsing helpers

    static func looksLikeMention(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("@") || lower.contains("mencionou") || lower.contains("mentioned you")
    }

    static func snippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 90 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 90)
        return String(trimmed[..<end]) + "…"
    }

    private static func parseNotificationPayload(_ data: Data) -> (title: String, body: String)? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            if let parsed = extractTitleBody(from: plist) { return parsed }
        }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            return extractFromStrings(text)
        }
        let printable = data.compactMap { byte -> Character? in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : nil
        }
        return extractFromStrings(String(printable))
    }

    private static func extractTitleBody(from object: Any) -> (title: String, body: String)? {
        if let dict = object as? [String: Any] {
            let title = stringValue(dict, keys: ["title", "req", "appName"])
            let body = stringValue(dict, keys: ["body", "subtitle", "message"])
            if let title, let body, !title.isEmpty { return (title, body) }
            for value in dict.values {
                if let nested = extractTitleBody(from: value) { return nested }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = extractTitleBody(from: value) { return nested }
            }
        }
        return nil
    }

    private static func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func extractFromStrings(_ text: String) -> (title: String, body: String)? {
        let titlePatterns = [#"\"title\"\s*:\s*\"([^\"]{2,80})\""#, #"title=([^\n]{2,80})"#]
        let bodyPatterns = [#"\"body\"\s*:\s*\"([^\"]{2,160})\""#, #"body=([^\n]{2,160})"#]
        func firstMatch(_ patterns: [String]) -> String? {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
            }
            return nil
        }
        if let title = firstMatch(titlePatterns) {
            return (title, firstMatch(bodyPatterns) ?? "Nova mensagem")
        }
        return nil
    }
}

private struct TeamsStubRow: Decodable {
    let sender: String
    let body: String
    let mentioned: Bool?
    /// Missing or false: do not emit. Old stubs without this field stay silent.
    let unread: Bool?
}
