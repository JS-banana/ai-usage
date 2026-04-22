import XCTest
import Foundation
import Domain
import Ingestion
@testable import Persistence

final class LiveDatabaseTests: XCTestCase {
    func testDatabaseInitializesAndMigrates() async throws {
        let (database, databasePath) = try makeDatabase()
        _ = database
        XCTAssertTrue(FileManager.default.fileExists(atPath: databasePath))
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
            totalTokens: 175
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
        XCTAssertEqual(metrics.sessionCount, 1)
        XCTAssertEqual(metrics.activeSources, 1)

        let sessions = try await database.recentSessions(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.totalTokens, 175)

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
            totalTokens: 160
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
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let databasePath = tempDirectory.appendingPathComponent("usage.sqlite").path
        let configuration = PersistenceConfiguration(location: DatabaseLocation(path: databasePath))
        return (try LiveDatabase(configuration: configuration), databasePath)
    }
}
