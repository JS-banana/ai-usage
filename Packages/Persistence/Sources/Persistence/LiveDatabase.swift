import Foundation
import GRDB
import Domain
import Ingestion
import Support

public actor LiveDatabase: ImportPersistence, AnalyticsQuerying {
    private let manager: DatabaseManager

    public init(configuration: PersistenceConfiguration) throws {
        self.manager = try DatabaseManager(configuration: configuration)
    }

    public nonisolated static func appSupportConfiguration() throws -> PersistenceConfiguration {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("AIUsageLocal", isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("usage.sqlite")
        return PersistenceConfiguration(location: DatabaseLocation(path: databaseURL.path))
    }

    public func unchangedFilePaths(sourceID: String, fingerprintsByPath: [String: String]) async throws -> Set<String> {
        try await manager.dbQueue.read { db in
            var unchanged = Set<String>()
            for (path, fingerprint) in fingerprintsByPath {
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT fingerprint FROM \(TableNames.sourceFiles) WHERE source_id = ? AND path = ?",
                    arguments: [sourceID, path]
                )
                if row?["fingerprint"] == fingerprint {
                    unchanged.insert(path)
                }
            }
            return unchanged
        }
    }

    public func persist(batch: NormalizedImportBatch, trigger: ImportTrigger) async throws -> ImportRun {
        let runID = StableID.make([batch.source.id, String(Date().timeIntervalSince1970), trigger.rawValue])
        let startedAt = Date()
        let status: ImportRunStatus = batch.diagnostics.contains(where: { $0.severity == .error }) || batch.skippedRecords > 0 ? .partial : .succeeded

        try await manager.dbQueue.write { db in
            try Self.upsertSource(batch.source, db: db, at: startedAt)
            try Self.upsertSourceFiles(batch.sourceFiles, runID: runID, db: db)
            try Self.insertImportRun(
                id: runID,
                sourceID: batch.source.id,
                startedAt: startedAt,
                finishedAt: startedAt,
                status: status,
                trigger: trigger,
                totalFiles: batch.sourceFiles.count,
                totalEvents: batch.events.count,
                totalSessions: batch.sessions.count,
                skippedRecords: batch.skippedRecords,
                db: db
            )
            try Self.upsertEvents(batch.events, db: db)
            try Self.upsertSessions(batch.sessions, db: db)
            try Self.insertDiagnostics(batch.diagnostics, runID: runID, createdAt: startedAt, db: db)
        }

        return ImportRun(
            id: runID,
            startedAt: startedAt,
            finishedAt: startedAt,
            status: status,
            trigger: trigger,
            totalFiles: batch.sourceFiles.count,
            totalEvents: batch.events.count,
            totalSessions: batch.sessions.count,
            skippedRecords: batch.skippedRecords
        )
    }

    public func dashboardMetrics(start: Date?, end: Date?) async throws -> DashboardMetrics {
        try await dashboardMetrics(start: start, end: end, sourceIDs: [])
    }

    public func dashboardMetrics(start: Date?, end: Date?, sourceIDs: [String]) async throws -> DashboardMetrics {
        try await manager.dbQueue.read { db in
            let range = SQLRange(start: start, end: end, column: "timestamp", sourceIDs: sourceIDs)
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    COALESCE(SUM(total_tokens), 0) AS total_tokens,
                    COUNT(DISTINCT id) AS event_count,
                    COUNT(DISTINCT source_id) AS active_sources
                FROM \(TableNames.usageEvents)
                \(range.whereClause)
                """,
                arguments: range.arguments
            )
            let sessionRange = SQLRange(start: start, end: end, column: "ended_at", sourceIDs: sourceIDs)
            let sessionCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(TableNames.sessions) \(sessionRange.whereClause)",
                arguments: sessionRange.arguments
            ) ?? 0
            let total: Int = row?["total_tokens"] ?? 0
            let activeSources: Int = row?["active_sources"] ?? 0
            return DashboardMetrics(
                todayTokens: total,
                sevenDayTokens: total,
                sessionCount: sessionCount,
                activeSources: activeSources
            )
        }
    }

    public func trend(start: Date?, end: Date?, granularity: TrendGranularity, calendar: Calendar) async throws -> [BucketPoint] {
        try await trend(start: start, end: end, granularity: granularity, calendar: calendar, sourceIDs: [])
    }

    public func trend(start: Date?, end: Date?, granularity: TrendGranularity, calendar: Calendar, sourceIDs: [String]) async throws -> [BucketPoint] {
        let events = try await usageEvents(start: start, end: end, sourceIDs: sourceIDs)
        let grouped: [Date: Int]
        switch granularity {
        case .daily:
            grouped = Dictionary(grouping: events, by: { calendar.startOfDay(for: $0.timestamp) })
                .mapValues { $0.reduce(0) { $0 + $1.totalTokens } }
        case .hourly:
            grouped = Dictionary(grouping: events, by: {
                let components = calendar.dateComponents([.year, .month, .day, .hour], from: $0.timestamp)
                return calendar.date(from: components) ?? calendar.startOfDay(for: $0.timestamp)
            }).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = granularity == .daily ? "MM-dd" : "MM-dd HH:00"
        let idFormatter = DateFormatter()
        idFormatter.calendar = calendar
        idFormatter.dateFormat = granularity == .daily ? "yyyy-MM-dd" : "yyyy-MM-dd HH:00"

        return grouped.keys.sorted().map { bucket in
            BucketPoint(id: idFormatter.string(from: bucket), label: formatter.string(from: bucket), value: grouped[bucket, default: 0])
        }
    }

    public func breakdownBySource(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem] {
        try await groupedBreakdown(groupColumn: "source_id", valueColumn: "total_tokens", start: start, end: end, limit: limit, sourceIDs: [])
    }

    public func cachedBreakdownBySource(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem] {
        try await groupedBreakdown(groupColumn: "source_id", valueColumn: "cached_tokens", start: start, end: end, limit: limit, sourceIDs: [])
    }

    public func breakdownByModel(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem] {
        try await groupedBreakdown(groupColumn: "model", valueColumn: "total_tokens", start: start, end: end, limit: limit, sourceIDs: [])
    }

    public func breakdownByProject(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem] {
        try await groupedBreakdown(groupColumn: "project", valueColumn: "total_tokens", start: start, end: end, limit: limit, sourceIDs: [])
    }

    public func recentSessions(limit: Int) async throws -> [SessionSummary] {
        try await sessions(filter: QueryFilters(), limit: limit)
    }

    public func sessions(filter: QueryFilters, limit: Int? = nil) async throws -> [SessionSummary] {
        try await manager.dbQueue.read { db in
            var clauses: [String] = []
            var arguments = StatementArguments()

            if let start = filter.startDate {
                clauses.append("ended_at >= ?")
                arguments += [start]
            }
            if let end = filter.endDate {
                clauses.append("ended_at <= ?")
                arguments += [end]
            }
            if filter.sourceIDs.isEmpty == false {
                clauses.append("source_id IN (\(Array(repeating: "?", count: filter.sourceIDs.count).joined(separator: ",")))")
                arguments += StatementArguments(filter.sourceIDs)
            }

            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let limitClause = limit.map { "LIMIT \($0)" } ?? ""
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, source_id, model, project, started_at, ended_at, messages, total_tokens, file_path
                FROM \(TableNames.sessions)
                \(whereClause)
                ORDER BY ended_at DESC
                \(limitClause)
                """,
                arguments: arguments
            )
            return rows.map(Self.makeSessionSummary)
        }
    }

    public func sourceHealthOverview() async throws -> [SourceHealth] {
        try await manager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    s.id,
                    s.display_name,
                    COALESCE(sf.file_count, 0) AS file_count,
                    COALESCE(ss.session_count, 0) AS session_count,
                    ir.finished_at AS last_scan,
                    COALESCE(diag.error_count, 0) AS error_count
                FROM \(TableNames.sources) s
                LEFT JOIN (
                    SELECT source_id, COUNT(*) AS file_count
                    FROM \(TableNames.sourceFiles)
                    GROUP BY source_id
                ) sf ON sf.source_id = s.id
                LEFT JOIN (
                    SELECT source_id, COUNT(*) AS session_count
                    FROM \(TableNames.sessions)
                    GROUP BY source_id
                ) ss ON ss.source_id = s.id
                LEFT JOIN (
                    SELECT ir1.source_id, ir1.finished_at
                    FROM \(TableNames.importRuns) ir1
                    INNER JOIN (
                        SELECT source_id, MAX(started_at) AS latest_started
                        FROM \(TableNames.importRuns)
                        GROUP BY source_id
                    ) latest ON latest.source_id = ir1.source_id AND latest.latest_started = ir1.started_at
                ) ir ON ir.source_id = s.id
                LEFT JOIN (
                    SELECT source_id, COUNT(*) AS error_count
                    FROM \(TableNames.parserDiagnostics)
                    WHERE severity = 'error'
                    GROUP BY source_id
                ) diag ON diag.source_id = s.id
                ORDER BY s.display_name ASC
                """
            )

            return rows.map { row in
                let sourceID: String = row["id"]
                let name: String = row["display_name"]
                let fileCount: Int = row["file_count"]
                let sessionCount: Int = row["session_count"]
                let lastScan: Date? = row["last_scan"]
                let errorCount: Int = row["error_count"]

                let status: SourceStatus
                let message: String
                if fileCount == 0 {
                    status = .warning
                    message = "未发现数据文件"
                } else if errorCount > 0 {
                    status = .warning
                    message = "已导入 \(sessionCount) 个会话，存在解析错误"
                } else if sessionCount == 0 {
                    status = .warning
                    message = "发现文件但未解析出有效记录"
                } else {
                    status = .ready
                    message = "已导入 \(sessionCount) 个会话"
                }

                return SourceHealth(
                    id: sourceID,
                    name: name,
                    discoveredFiles: fileCount,
                    importedSessions: sessionCount,
                    lastScan: lastScan,
                    status: status,
                    message: message
                )
            }
        }
    }

    public func latestDiagnostics(sourceID: String, limit: Int) async throws -> [ParserDiagnostic] {
        try await manager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, severity, source_id, file_path, message
                FROM \(TableNames.parserDiagnostics)
                WHERE source_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                arguments: [sourceID, limit]
            )
            return rows.map {
                ParserDiagnostic(
                    id: $0["id"],
                    severity: ParserDiagnostic.Severity(rawValue: $0["severity"]) ?? .warning,
                    source: $0["source_id"],
                    filePath: $0["file_path"],
                    message: $0["message"]
                )
            }
        }
    }

    private func usageEvents(start: Date?, end: Date?, sourceIDs: [String]) async throws -> [UsageEvent] {
        try await manager.dbQueue.read { db in
            let range = SQLRange(start: start, end: end, column: "timestamp", sourceIDs: sourceIDs)
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, source_id, model, project, timestamp, input_tokens, output_tokens, cached_tokens, total_tokens
                FROM \(TableNames.usageEvents)
                \(range.whereClause)
                ORDER BY timestamp ASC
                """,
                arguments: range.arguments
            )
            return rows.map { row in
                UsageEvent(
                    id: row["id"],
                    source: row["source_id"],
                    model: row["model"],
                    project: row["project"],
                    timestamp: row["timestamp"],
                    inputTokens: row["input_tokens"],
                    outputTokens: row["output_tokens"],
                    cachedTokens: row["cached_tokens"],
                    totalTokens: row["total_tokens"]
                )
            }
        }
    }

    private func groupedBreakdown(groupColumn: String, valueColumn: String, start: Date?, end: Date?, limit: Int, sourceIDs: [String]) async throws -> [BreakdownItem] {
        try await manager.dbQueue.read { db in
            let range = SQLRange(start: start, end: end, column: "timestamp", sourceIDs: sourceIDs)
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(groupColumn) AS bucket, COALESCE(SUM(\(valueColumn)), 0) AS total
                FROM \(TableNames.usageEvents)
                \(range.whereClause)
                GROUP BY \(groupColumn)
                ORDER BY total DESC
                LIMIT \(limit)
                """,
                arguments: range.arguments
            )
            return rows.map {
                let name: String = $0["bucket"]
                let value: Int = $0["total"]
                return BreakdownItem(id: name, name: name, value: value)
            }
        }
    }

    private static func upsertSource(_ source: SourceDescriptor, db: Database, at timestamp: Date) throws {
        try db.execute(
            sql: """
            INSERT INTO \(TableNames.sources) (id, display_name, enabled, built_in, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                enabled = excluded.enabled,
                built_in = excluded.built_in,
                updated_at = excluded.updated_at
            """,
            arguments: [source.id, source.displayName, source.enabledByDefault, source.builtIn, timestamp, timestamp]
        )
    }

    private static func upsertSourceFiles(_ sourceFiles: [TrackedSourceFile], runID: String, db: Database) throws {
        for file in sourceFiles {
            try db.execute(
                sql: """
                INSERT INTO \(TableNames.sourceFiles) (id, source_id, path, fingerprint, last_seen_at, last_import_run_id)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    fingerprint = excluded.fingerprint,
                    last_seen_at = excluded.last_seen_at,
                    last_import_run_id = excluded.last_import_run_id
                """,
                arguments: [file.id, file.sourceID, file.path, file.fingerprint, file.lastSeenAt, runID]
            )
        }
    }

    private static func insertImportRun(
        id: String,
        sourceID: String,
        startedAt: Date,
        finishedAt: Date,
        status: ImportRunStatus,
        trigger: ImportTrigger,
        totalFiles: Int,
        totalEvents: Int,
        totalSessions: Int,
        skippedRecords: Int,
        db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO \(TableNames.importRuns) (id, source_id, started_at, finished_at, status, trigger, total_files, total_events, total_sessions, skipped_records)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [id, sourceID, startedAt, finishedAt, status.rawValue, trigger.rawValue, totalFiles, totalEvents, totalSessions, skippedRecords]
        )
    }

    private static func upsertEvents(_ events: [UsageEvent], db: Database) throws {
        for event in events {
            try db.execute(
                sql: """
                INSERT INTO \(TableNames.usageEvents) (id, source_id, model, project, timestamp, input_tokens, output_tokens, cached_tokens, total_tokens)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    model = excluded.model,
                    project = excluded.project,
                    timestamp = excluded.timestamp,
                    input_tokens = excluded.input_tokens,
                    output_tokens = excluded.output_tokens,
                    cached_tokens = excluded.cached_tokens,
                    total_tokens = excluded.total_tokens
                """,
                arguments: [event.id, event.source, event.model, event.project, event.timestamp, event.inputTokens, event.outputTokens, event.cachedTokens, event.totalTokens]
            )
        }
    }

    private static func upsertSessions(_ sessions: [SessionSummary], db: Database) throws {
        for session in sessions {
            try db.execute(
                sql: """
                INSERT INTO \(TableNames.sessions) (id, source_id, model, project, started_at, ended_at, messages, total_tokens, file_path)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    model = excluded.model,
                    project = excluded.project,
                    started_at = excluded.started_at,
                    ended_at = excluded.ended_at,
                    messages = excluded.messages,
                    total_tokens = excluded.total_tokens,
                    file_path = excluded.file_path
                """,
                arguments: [session.id, session.source, session.model, session.project, session.startedAt, session.endedAt, session.messages, session.totalTokens, session.filePath]
            )
        }
    }

    private static func insertDiagnostics(_ diagnostics: [ParserDiagnostic], runID: String, createdAt: Date, db: Database) throws {
        for diagnostic in diagnostics {
            try db.execute(
                sql: """
                INSERT INTO \(TableNames.parserDiagnostics) (id, import_run_id, source_id, file_path, severity, message, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    import_run_id = excluded.import_run_id,
                    severity = excluded.severity,
                    message = excluded.message,
                    created_at = excluded.created_at
                """,
                arguments: [diagnostic.id, runID, diagnostic.source, diagnostic.filePath, diagnostic.severity.rawValue, diagnostic.message, createdAt]
            )
        }
    }

    private static func makeSessionSummary(row: Row) -> SessionSummary {
        SessionSummary(
            id: row["id"],
            source: row["source_id"],
            model: row["model"],
            project: row["project"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            messages: row["messages"],
            totalTokens: row["total_tokens"],
            filePath: row["file_path"]
        )
    }
}

private struct SQLRange {
    let whereClause: String
    let arguments: StatementArguments

    init(start: Date?, end: Date?, column: String, sourceIDs: [String] = []) {
        var clauses: [String] = []
        var arguments = StatementArguments()
        if let start {
            clauses.append("\(column) >= ?")
            arguments += [start]
        }
        if let end {
            clauses.append("\(column) <= ?")
            arguments += [end]
        }
        if sourceIDs.isEmpty == false {
            clauses.append("source_id IN (\(Array(repeating: "?", count: sourceIDs.count).joined(separator: ",")))")
            arguments += StatementArguments(sourceIDs)
        }
        self.whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        self.arguments = arguments
    }
}
