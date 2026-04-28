import XCTest
import Foundation
import Domain
@testable import Persistence

final class LiveDatabaseTests: XCTestCase {
    func testDatabaseInitializesAndMigrates() async throws {
        let (database, databasePath) = try makeDatabase()
        _ = database
        XCTAssertTrue(FileManager.default.fileExists(atPath: databasePath))
    }

    func testDatabaseCreatesAccountSnapshotTables() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let databasePath = tempDirectory.appendingPathComponent("usage.sqlite").path
        let manager = try DatabaseManager(configuration: PersistenceConfiguration(location: DatabaseLocation(path: databasePath)))

        let tableNames = try manager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                """
            )
        }

        XCTAssertTrue(tableNames.contains(TableNames.providerAccounts))
        XCTAssertTrue(tableNames.contains(TableNames.accountRefreshRuns))
        XCTAssertTrue(tableNames.contains(TableNames.accountSnapshots))
        XCTAssertTrue(tableNames.contains(TableNames.allowanceWindows))
        XCTAssertTrue(tableNames.contains(TableNames.accountDiagnostics))
    }

    func testAppSupportConfigurationUsesAiUsageDirectoryWhenFresh() throws {
        let appSupportURL = try makeTemporaryDirectory()

        let configuration = try LiveDatabase.appSupportConfiguration(
            fileManager: .default,
            appSupportURL: appSupportURL
        )

        XCTAssertEqual(
            configuration.location.path,
            appSupportURL
                .appendingPathComponent("AiUsage", isDirectory: true)
                .appendingPathComponent("usage.sqlite")
                .path
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appSupportURL.appendingPathComponent("AiUsage", isDirectory: true).path
            )
        )
    }

    func testAppSupportConfigurationMigratesLegacyDirectory() throws {
        let fileManager = FileManager.default
        let appSupportURL = try makeTemporaryDirectory()
        let legacyDirectoryURL = appSupportURL.appendingPathComponent("AIUsageLocal", isDirectory: true)
        try fileManager.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        let legacyDatabaseURL = legacyDirectoryURL.appendingPathComponent("usage.sqlite")
        try Data("legacy".utf8).write(to: legacyDatabaseURL)

        let configuration = try LiveDatabase.appSupportConfiguration(
            fileManager: fileManager,
            appSupportURL: appSupportURL
        )

        let migratedDatabaseURL = appSupportURL
            .appendingPathComponent("AiUsage", isDirectory: true)
            .appendingPathComponent("usage.sqlite")
        XCTAssertEqual(configuration.location.path, migratedDatabaseURL.path)
        XCTAssertTrue(fileManager.fileExists(atPath: migratedDatabaseURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyDatabaseURL.path))
    }

    func testPersistBatchFeedsQueries() async throws {
        let (database, _) = try makeDatabase()
        let now = Date()
        let source = SourceDescriptor(id: "claude-code", displayName: "Claude Code")
        let file = TrackedSourceFile(
            id: "file-1",
            sourceID: source.id,
            path: "/tmp/claude/session.jsonl",
            fingerprint: "fp-1",
            lastSeenAt: now
        )
        let event = UsageEvent(
            id: "event-1",
            source: source.id,
            model: "claude-sonnet-4",
            project: "demo",
            timestamp: now,
            inputTokens: 100,
            outputTokens: 50,
            cachedTokens: 25,
            totalTokens: 175,
            requestCount: 1
        )
        let session = SessionSummary(
            id: "session-1",
            source: source.id,
            model: "claude-sonnet-4",
            project: "demo",
            startedAt: now,
            endedAt: now,
            messages: 1,
            totalTokens: 175,
            requestCount: 1,
            filePath: file.path
        )
        let batch = NormalizedImportBatch(
            source: source,
            sourceFiles: [file],
            events: [event],
            sessions: [session],
            diagnostics: [],
            skippedRecords: 0
        )

        _ = try await database.persist(batch: batch, trigger: .startup)

        let metrics = try await database.dashboardMetrics(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        XCTAssertEqual(metrics.todayTokens, 175)
        XCTAssertEqual(metrics.todayRequests, 1)
        XCTAssertEqual(metrics.sessionCount, 1)
        XCTAssertEqual(metrics.activeSources, 1)

        let sessions = try await database.recentSessions(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.totalTokens, 175)
        XCTAssertEqual(sessions.first?.requestCount, 1)

        let health = try await database.sourceHealthOverview()
        XCTAssertEqual(health.count, 1)
        XCTAssertEqual(health.first?.discoveredFiles, 1)
        XCTAssertEqual(health.first?.importedSessions, 1)
    }

    func testRepeatedPersistDoesNotDuplicateUsage() async throws {
        let (database, _) = try makeDatabase()
        let now = Date()
        let source = SourceDescriptor(id: "codex", displayName: "Codex CLI")
        let file = TrackedSourceFile(
            id: "file-1",
            sourceID: source.id,
            path: "/tmp/codex/rollout.jsonl",
            fingerprint: "fp-1",
            lastSeenAt: now
        )
        let event = UsageEvent(
            id: "event-1",
            source: source.id,
            model: "gpt-5-codex",
            project: "demo",
            timestamp: now,
            inputTokens: 120,
            outputTokens: 30,
            cachedTokens: 10,
            totalTokens: 160,
            requestCount: 1
        )
        let session = SessionSummary(
            id: "session-1",
            source: source.id,
            model: "gpt-5-codex",
            project: "demo",
            startedAt: now,
            endedAt: now,
            messages: 1,
            totalTokens: 160,
            requestCount: 1,
            filePath: file.path
        )
        let batch = NormalizedImportBatch(
            source: source,
            sourceFiles: [file],
            events: [event],
            sessions: [session],
            diagnostics: [],
            skippedRecords: 0
        )

        _ = try await database.persist(batch: batch, trigger: .startup)
        _ = try await database.persist(batch: batch, trigger: .manual)

        let metrics = try await database.dashboardMetrics(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        XCTAssertEqual(metrics.todayTokens, 160)
        XCTAssertEqual(metrics.todayRequests, 1)
        XCTAssertEqual(metrics.sessionCount, 1)
    }

    func testUnchangedFilePathsMatchesPersistedFingerprint() async throws {
        let (database, _) = try makeDatabase()
        let now = Date()
        let source = SourceDescriptor(id: "claude-code", displayName: "Claude Code")
        let file = TrackedSourceFile(
            id: "file-1",
            sourceID: source.id,
            path: "/tmp/claude/session.jsonl",
            fingerprint: "fp-1",
            lastSeenAt: now
        )
        let batch = NormalizedImportBatch(
            source: source,
            sourceFiles: [file],
            events: [],
            sessions: [],
            diagnostics: [],
            skippedRecords: 0
        )

        _ = try await database.persist(batch: batch, trigger: .startup)

        let unchanged = try await database.unchangedFilePaths(
            sourceID: source.id,
            fingerprintsByPath: [file.path: "fp-1", "/tmp/claude/other.jsonl": "fp-2"]
        )
        XCTAssertEqual(unchanged, Set([file.path]))
    }

    private func makeDatabase() throws -> (LiveDatabase, String) {
        let tempDirectory = try makeTemporaryDirectory()
        let databasePath = tempDirectory.appendingPathComponent("usage.sqlite").path
        let configuration = PersistenceConfiguration(location: DatabaseLocation(path: databasePath))
        return (try LiveDatabase(configuration: configuration), databasePath)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
    }
}
