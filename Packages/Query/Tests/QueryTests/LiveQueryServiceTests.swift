import XCTest
import Foundation
import Domain
import Persistence
@testable import Query

final class LiveQueryServiceTests: XCTestCase {
    func testDashboardQueryReturnsSummaryTrendAndCachedBreakdown() async throws {
        let database = try makeDatabase()
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
            outputTokens: 60,
            cachedTokens: 40,
            totalTokens: 200,
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
            totalTokens: 200,
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

        let dashboard = LiveDashboardQueryService(analytics: database)
        let sessionsQuery = LiveSessionsQueryService(analytics: database)
        let sourceHealth = LiveSourceHealthQueryService(analytics: database)
        let range = DateRange(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))

        let summary = try await dashboard.summary(range: range)
        XCTAssertEqual(summary.metrics.todayTokens, 200)
        XCTAssertEqual(summary.metrics.todayRequests, 1)
        XCTAssertEqual(summary.metrics.sessionCount, 1)

        let trend = try await dashboard.trend(range: range, granularity: .daily)
        XCTAssertEqual(trend.count, 1)
        XCTAssertEqual(trend.first?.value, 200)

        let cachedBreakdown = try await dashboard.cachedBreakdownBySource(range: range, limit: 8)
        XCTAssertEqual(cachedBreakdown.first?.id, "claude-code")
        XCTAssertEqual(cachedBreakdown.first?.value, 40)

        let recent = try await sessionsQuery.recentSessions(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.summary.totalTokens, 200)

        let health = try await sourceHealth.sourceOverview()
        XCTAssertEqual(health.count, 1)
        XCTAssertEqual(health.first?.health.importedSessions, 1)
    }

    func testDashboardQueryCanFilterByProvider() async throws {
        let database = try makeDatabase()
        let now = Date()

        let claudeSource = SourceDescriptor(id: "claude-code", displayName: "Claude Code")
        let claudeBatch = NormalizedImportBatch(
            source: claudeSource,
            sourceFiles: [
                TrackedSourceFile(id: "claude-file", sourceID: claudeSource.id, path: "/tmp/claude.jsonl", fingerprint: "fp-1", lastSeenAt: now)
            ],
            events: [
                UsageEvent(id: "claude-event", source: claudeSource.id, model: "claude-sonnet-4", project: "demo", timestamp: now, inputTokens: 100, outputTokens: 50, cachedTokens: 25, totalTokens: 175)
            ],
            sessions: [
                SessionSummary(id: "claude-session", source: claudeSource.id, model: "claude-sonnet-4", project: "demo", startedAt: now, endedAt: now, messages: 1, totalTokens: 175, requestCount: 1, filePath: "/tmp/claude.jsonl")
            ],
            diagnostics: [],
            skippedRecords: 0
        )

        let codexSource = SourceDescriptor(id: "codex", displayName: "Codex CLI")
        let codexBatch = NormalizedImportBatch(
            source: codexSource,
            sourceFiles: [
                TrackedSourceFile(id: "codex-file", sourceID: codexSource.id, path: "/tmp/codex.jsonl", fingerprint: "fp-2", lastSeenAt: now)
            ],
            events: [
                UsageEvent(id: "codex-event", source: codexSource.id, model: "gpt-5-codex", project: "demo", timestamp: now, inputTokens: 300, outputTokens: 100, cachedTokens: 50, totalTokens: 450, requestCount: 1)
            ],
            sessions: [
                SessionSummary(id: "codex-session", source: codexSource.id, model: "gpt-5-codex", project: "demo", startedAt: now, endedAt: now, messages: 1, totalTokens: 450, requestCount: 1, filePath: "/tmp/codex.jsonl")
            ],
            diagnostics: [],
            skippedRecords: 0
        )

        _ = try await database.persist(batch: claudeBatch, trigger: .startup)
        _ = try await database.persist(batch: codexBatch, trigger: .startup)

        let dashboard = LiveDashboardQueryService(analytics: database)
        let range = DateRange(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))

        let claudeSummary = try await dashboard.summary(range: range, sourceIDs: ["claude-code"])
        XCTAssertEqual(claudeSummary.metrics.todayTokens, 175)
        XCTAssertEqual(claudeSummary.metrics.todayRequests, 1)
        XCTAssertEqual(claudeSummary.metrics.sessionCount, 1)

        let codexSummary = try await dashboard.summary(range: range, sourceIDs: ["codex"])
        XCTAssertEqual(codexSummary.metrics.todayTokens, 450)
        XCTAssertEqual(codexSummary.metrics.todayRequests, 1)
        XCTAssertEqual(codexSummary.metrics.sessionCount, 1)

        let codexTrend = try await dashboard.trend(range: range, granularity: .daily, sourceIDs: ["codex"])
        XCTAssertEqual(codexTrend.count, 1)
        XCTAssertEqual(codexTrend.first?.value, 450)
    }

    func testSessionsQueryFiltersByModelAndProject() async throws {
        let database = try makeDatabase()
        let now = Date()
        let source = SourceDescriptor(id: "claude-code", displayName: "Claude Code")
        let batch = NormalizedImportBatch(
            source: source,
            sourceFiles: [
                TrackedSourceFile(id: "file-1", sourceID: source.id, path: "/tmp/demo-a.jsonl", fingerprint: "fp-1", lastSeenAt: now),
                TrackedSourceFile(id: "file-2", sourceID: source.id, path: "/tmp/demo-b.jsonl", fingerprint: "fp-2", lastSeenAt: now)
            ],
            events: [],
            sessions: [
                SessionSummary(id: "session-1", source: source.id, model: "claude-sonnet-4", project: "alpha", startedAt: now, endedAt: now, messages: 1, totalTokens: 100, requestCount: 1, filePath: "/tmp/demo-a.jsonl"),
                SessionSummary(id: "session-2", source: source.id, model: "claude-haiku-3", project: "beta", startedAt: now, endedAt: now, messages: 1, totalTokens: 80, requestCount: 1, filePath: "/tmp/demo-b.jsonl")
            ],
            diagnostics: [],
            skippedRecords: 0
        )

        _ = try await database.persist(batch: batch, trigger: .startup)

        let sessionsQuery = LiveSessionsQueryService(analytics: database)
        let modelFiltered = try await sessionsQuery.sessions(filter: SessionFilter(models: ["claude-sonnet-4"]))
        XCTAssertEqual(modelFiltered.map(\.summary.id), ["session-1"])

        let projectFiltered = try await sessionsQuery.sessions(filter: SessionFilter(projects: ["beta"]))
        XCTAssertEqual(projectFiltered.map(\.summary.id), ["session-2"])
    }

    private func makeDatabase() throws -> LiveDatabase {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let databasePath = tempDirectory.appendingPathComponent("usage.sqlite").path
        return try LiveDatabase(configuration: PersistenceConfiguration(location: DatabaseLocation(path: databasePath)))
    }
}
