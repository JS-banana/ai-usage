import Foundation
import GRDB

public enum PersistenceMigrator {
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_usage_tables") { db in
            try db.create(table: TableNames.sources, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("display_name", .text).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("built_in", .boolean).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: TableNames.sourceFiles, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("fingerprint", .text).notNull()
                t.column("last_seen_at", .datetime).notNull()
                t.column("last_import_run_id", .text)
            }
            try db.create(index: "idx_source_files_source_path", on: TableNames.sourceFiles, columns: ["source_id", "path"], unique: true, ifNotExists: true)

            try db.create(table: TableNames.importRuns, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("finished_at", .datetime)
                t.column("status", .text).notNull()
                t.column("trigger", .text).notNull()
                t.column("total_files", .integer).notNull()
                t.column("total_events", .integer).notNull()
                t.column("total_sessions", .integer).notNull()
                t.column("skipped_records", .integer).notNull()
            }
            try db.create(index: "idx_import_runs_source_started", on: TableNames.importRuns, columns: ["source_id", "started_at"], ifNotExists: true)

            try db.create(table: TableNames.usageEvents, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("project", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("input_tokens", .integer).notNull()
                t.column("output_tokens", .integer).notNull()
                t.column("cached_tokens", .integer).notNull()
                t.column("total_tokens", .integer).notNull()
            }
            try db.create(index: "idx_usage_events_timestamp", on: TableNames.usageEvents, columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_usage_events_source_timestamp", on: TableNames.usageEvents, columns: ["source_id", "timestamp"], ifNotExists: true)

            try db.create(table: TableNames.sessions, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("project", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime).notNull()
                t.column("messages", .integer).notNull()
                t.column("total_tokens", .integer).notNull()
                t.column("file_path", .text).notNull()
            }
            try db.create(index: "idx_sessions_ended_at", on: TableNames.sessions, columns: ["ended_at"], ifNotExists: true)
            try db.create(index: "idx_sessions_source_ended", on: TableNames.sessions, columns: ["source_id", "ended_at"], ifNotExists: true)

            try db.create(table: TableNames.parserDiagnostics, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("import_run_id", .text).notNull().references(TableNames.importRuns, onDelete: .cascade)
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("file_path", .text).notNull()
                t.column("severity", .text).notNull()
                t.column("message", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_diagnostics_source_created", on: TableNames.parserDiagnostics, columns: ["source_id", "created_at"], ifNotExists: true)

            try db.create(table: TableNames.dailyBuckets, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references(TableNames.sources, onDelete: .cascade)
                t.column("bucket_date", .date).notNull()
                t.column("total_tokens", .integer).notNull()
                t.column("session_count", .integer).notNull()
            }
            try db.create(index: "idx_daily_buckets_source_date", on: TableNames.dailyBuckets, columns: ["source_id", "bucket_date"], unique: true, ifNotExists: true)
        }

        return migrator
    }
}
