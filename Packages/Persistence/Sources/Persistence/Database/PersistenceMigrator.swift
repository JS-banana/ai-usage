import Foundation
import GRDB
import Domain

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

        migrator.registerMigration("v2_add_request_count_metrics") { db in
            try db.alter(table: TableNames.usageEvents) { t in
                t.add(column: "request_count", .integer).notNull().defaults(to: 0)
                t.add(column: "request_semantic", .text).notNull().defaults(to: RequestSemantic.assistantResponse.rawValue)
                t.add(column: "request_confidence", .text).notNull().defaults(to: MetricConfidence.estimated.rawValue)
            }

            try db.alter(table: TableNames.sessions) { t in
                t.add(column: "request_count", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v3_create_account_snapshot_tables") { db in
            try db.create(table: TableNames.providerAccounts, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references(TableNames.sources, column: "id", onDelete: .cascade)
                t.column("account_label", .text).notNull()
                t.column("backend_label", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: TableNames.accountRefreshRuns, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("account_id", .text).notNull().references(TableNames.providerAccounts, onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("finished_at", .datetime)
                t.column("status", .text).notNull()
                t.column("diagnostics_count", .integer).notNull()
            }

            try db.create(table: TableNames.accountSnapshots, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("account_id", .text).notNull().references(TableNames.providerAccounts, onDelete: .cascade)
                t.column("refresh_run_id", .text).references(TableNames.accountRefreshRuns, onDelete: .setNull)
                t.column("captured_at", .datetime).notNull()
                t.column("freshness_date", .datetime).notNull()
                t.column("is_stale", .boolean).notNull()
            }

            try db.create(table: TableNames.allowanceWindows, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("snapshot_id", .text).notNull().references(TableNames.accountSnapshots, onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("used", .double).notNull()
                t.column("limit_value", .double)
                t.column("remaining", .double)
                t.column("resets_at", .datetime)
            }

            try db.create(table: TableNames.accountDiagnostics, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("account_id", .text).notNull().references(TableNames.providerAccounts, onDelete: .cascade)
                t.column("snapshot_id", .text).references(TableNames.accountSnapshots, onDelete: .setNull)
                t.column("severity", .text).notNull()
                t.column("message", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(index: "idx_provider_accounts_provider", on: TableNames.providerAccounts, columns: ["provider_id"], ifNotExists: true)
            try db.create(index: "idx_account_refresh_runs_account", on: TableNames.accountRefreshRuns, columns: ["account_id", "started_at"], ifNotExists: true)
            try db.create(index: "idx_account_snapshots_account", on: TableNames.accountSnapshots, columns: ["account_id", "captured_at"], ifNotExists: true)
            try db.create(index: "idx_allowance_windows_snapshot", on: TableNames.allowanceWindows, columns: ["snapshot_id", "kind"], ifNotExists: true)
            try db.create(index: "idx_account_diagnostics_account", on: TableNames.accountDiagnostics, columns: ["account_id", "created_at"], ifNotExists: true)
        }

        return migrator
    }
}
