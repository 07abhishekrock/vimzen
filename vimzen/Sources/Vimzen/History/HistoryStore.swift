import Foundation
import SQLite3

public struct HistoryEntry: Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let domain: String
    public let title: String
    public let visitCount: Int
    public let typedCount: Int
    public let lastVisitTime: Date
}

public enum HistoryClearScope: Sendable {
    case all
    case today
    case domain(String)
}

public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.vimzen.history.db", qos: .utility)

    private init() {
        openDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let vimzenDir: URL
        if let testDir = TestEnvironment.dataDirectory {
            vimzenDir = testDir
        } else {
            guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return
            }
            vimzenDir = appSupport.appendingPathComponent("Vimzen", isDirectory: true)
        }

        try? fileManager.createDirectory(at: vimzenDir, withIntermediateDirectories: true)
        let dbURL = vimzenDir.appendingPathComponent("history.db")

        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            // Enable WAL mode for high performance and fast concurrent reads
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)

            createTables()
        } else {
            print("Failed to open SQLite history database at \(dbURL.path)")
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT NOT NULL,
            url TEXT NOT NULL,
            domain TEXT NOT NULL,
            title TEXT NOT NULL,
            visit_count INTEGER NOT NULL DEFAULT 1,
            typed_count INTEGER NOT NULL DEFAULT 0,
            first_visit_time INTEGER NOT NULL,
            last_visit_time INTEGER NOT NULL,
            UNIQUE(profile_id, url)
        );

        CREATE INDEX IF NOT EXISTS idx_visits_profile_frecency 
            ON visits(profile_id, last_visit_time DESC, visit_count DESC);

        CREATE INDEX IF NOT EXISTS idx_visits_profile_domain 
            ON visits(profile_id, domain);
        """

        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Recording

    public func recordVisit(
        url: URL,
        title: String,
        profileId: UUID,
        isTyped: Bool = false
    ) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return
        }

        let normalizedDomain = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let urlString = url.absoluteString
        let now = Int(Date().timeIntervalSince1970)
        let profileString = profileId.uuidString
        let typedVal = isTyped ? 1 : 0

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let query = """
            INSERT INTO visits (profile_id, url, domain, title, visit_count, typed_count, first_visit_time, last_visit_time)
            VALUES (?, ?, ?, ?, 1, ?, ?, ?)
            ON CONFLICT(profile_id, url) DO UPDATE SET
                title = CASE WHEN length(excluded.title) > 0 THEN excluded.title ELSE visits.title END,
                visit_count = visits.visit_count + 1,
                typed_count = visits.typed_count + excluded.typed_count,
                last_visit_time = excluded.last_visit_time;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (profileString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (urlString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (normalizedDomain as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (title as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 5, Int32(typedVal))
                sqlite3_bind_int64(stmt, 6, Int64(now))
                sqlite3_bind_int64(stmt, 7, Int64(now))

                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func updateTitle(url: URL, title: String, profileId: UUID) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let urlString = url.absoluteString
        let profileString = profileId.uuidString

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let query = "UPDATE visits SET title = ? WHERE profile_id = ? AND url = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (trimmedTitle as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (profileString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (urlString as NSString).utf8String, -1, nil)

                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Querying

    public func search(
        query: String,
        profileId: UUID,
        limit: Int = 100
    ) async -> [HistoryEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self, let db = self.db else {
                    continuation.resume(returning: [])
                    return
                }

                var entries: [HistoryEntry] = []
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let profileString = profileId.uuidString

                let sql: String
                if trimmed.isEmpty {
                    sql = """
                    SELECT url, domain, title, visit_count, typed_count, last_visit_time 
                    FROM visits 
                    WHERE profile_id = ? 
                    ORDER BY last_visit_time DESC 
                    LIMIT ?;
                    """
                } else {
                    sql = """
                    SELECT url, domain, title, visit_count, typed_count, last_visit_time 
                    FROM visits 
                    WHERE profile_id = ? AND (url LIKE ? OR title LIKE ? OR domain LIKE ?) 
                    ORDER BY last_visit_time DESC 
                    LIMIT ?;
                    """
                }

                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (profileString as NSString).utf8String, -1, nil)

                    if trimmed.isEmpty {
                        sqlite3_bind_int(stmt, 2, Int32(limit))
                    } else {
                        let pattern = "%\(trimmed)%"
                        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 3, (pattern as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 4, (pattern as NSString).utf8String, -1, nil)
                        sqlite3_bind_int(stmt, 5, Int32(limit))
                    }

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let rawUrl = sqlite3_column_text(stmt, 0),
                              let url = URL(string: String(cString: rawUrl)) else {
                            continue
                        }
                        let domain = String(cString: sqlite3_column_text(stmt, 1))
                        let title = String(cString: sqlite3_column_text(stmt, 2))
                        let visitCount = Int(sqlite3_column_int(stmt, 3))
                        let typedCount = Int(sqlite3_column_int(stmt, 4))
                        let lastVisit = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))

                        entries.append(
                            HistoryEntry(
                                id: "hist:\(profileString):\(url.absoluteString)",
                                url: url,
                                domain: domain,
                                title: title.isEmpty ? domain : title,
                                visitCount: visitCount,
                                typedCount: typedCount,
                                lastVisitTime: lastVisit
                            )
                        )
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: entries)
            }
        }
    }

    // MARK: - Pruning / Clear History

    public func clear(profileId: UUID, scope: HistoryClearScope = .all) {
        let profileString = profileId.uuidString

        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            switch scope {
            case .all:
                let sql = "DELETE FROM visits WHERE profile_id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (profileString as NSString).utf8String, -1, nil)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)

            case .today:
                let startOfDay = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
                let sql = "DELETE FROM visits WHERE profile_id = ? AND last_visit_time >= ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (profileString as NSString).utf8String, -1, nil)
                    sqlite3_bind_int64(stmt, 2, Int64(startOfDay))
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)

            case .domain(let dom):
                let normalized = dom.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
                let sql = "DELETE FROM visits WHERE profile_id = ? AND domain = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (profileString as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 2, (normalized as NSString).utf8String, -1, nil)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }
}
