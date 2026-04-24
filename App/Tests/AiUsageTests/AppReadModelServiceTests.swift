import XCTest
import Domain
import Ingestion
import ParserCore
import ProviderKit
import Query
@testable import AiUsage

final class AppReadModelServiceTests: XCTestCase {
    func testReadModelHonorsUserSelectedVisibleSources() async throws {
        let defaults = UserDefaults(suiteName: "AppReadModelServiceTests")!
        defaults.removePersistentDomain(forName: "AppReadModelServiceTests")
        AppPreferences.setSourceEnabled(false, sourceID: "codex", userDefaults: defaults)

        let service = AppReadModelService(
            sourceRegistry: SourceRegistryStub(),
            dashboardQuery: DashboardQueryStub(),
            sourceHealthQuery: SourceHealthQueryStub(),
            userDefaults: defaults
        )

        let snapshot = try await service.makeSnapshot(preferredTabID: nil)

        XCTAssertEqual(snapshot.providerTabs.map(\.id), ["overview", "claude-code"])
        XCTAssertEqual(snapshot.providerPreferences.count, 2)
        XCTAssertTrue(snapshot.providerPreferences.contains(where: { $0.id == "codex" && $0.isEnabled == false }))
        XCTAssertEqual(snapshot.overview.providerRows.map(\.id), ["claude-code"])
    }
}

private struct SourceRegistryStub: SourceRegistry {
    func allSources() -> [SourceDescriptor] { providerDescriptors().map(\.sourceDescriptor) }

    func providerDescriptors() -> [ProviderDescriptor] {
        [
            ProviderDescriptor(
                id: "claude-code",
                displayName: "Claude",
                capabilities: [.localUsageFacts, .accountQuotaSnapshots],
                backendKind: .hybrid,
                credentialKind: .apiKey,
                refreshPolicy: .manual
            ),
            ProviderDescriptor(
                id: "codex",
                displayName: "Codex",
                capabilities: [.localUsageFacts],
                backendKind: .localLogs,
                credentialKind: .none,
                refreshPolicy: .manual
            )
        ]
    }

    func enabledParsers() -> [any UsageParser] { [] }
}

private struct DashboardQueryStub: DashboardQueryServing {
    func summary(range: DateRange) async throws -> DashboardSummary { stubSummary }
    func summary(range: DateRange, sourceIDs: [String]) async throws -> DashboardSummary {
        DashboardSummary(metrics: DashboardMetrics(todayTokens: sourceIDs.count * 100, sevenDayTokens: sourceIDs.count * 700, todayRequests: sourceIDs.count, sevenDayRequests: sourceIDs.count * 7, sessionCount: sourceIDs.count, activeSources: sourceIDs.count))
    }
    func trend(range: DateRange, granularity: TrendGranularity) async throws -> [BucketPoint] { [] }
    func trend(range: DateRange, granularity: TrendGranularity, sourceIDs: [String]) async throws -> [BucketPoint] { [] }
    func breakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem] { [] }
    func cachedBreakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem] {
        [BreakdownItem(id: "claude-code", name: "Claude", value: 10), BreakdownItem(id: "codex", name: "Codex", value: 20)]
    }
    func breakdownByModel(range: DateRange, limit: Int) async throws -> [BreakdownItem] { [] }
    func breakdownByProject(range: DateRange, limit: Int) async throws -> [BreakdownItem] { [] }

    private var stubSummary: DashboardSummary {
        DashboardSummary(metrics: DashboardMetrics(todayTokens: 100, sevenDayTokens: 700, todayRequests: 1, sevenDayRequests: 7, sessionCount: 1, activeSources: 1))
    }
}

private struct SourceHealthQueryStub: SourceHealthQueryServing {
    func sourceOverview() async throws -> [SourceHealthItem] {
        [
            SourceHealthItem(id: "claude-code", health: SourceHealth(id: "claude-code", name: "Claude", discoveredFiles: 1, importedSessions: 2, lastScan: Date(), status: .ready, message: "正常")),
            SourceHealthItem(id: "codex", health: SourceHealth(id: "codex", name: "Codex", discoveredFiles: 1, importedSessions: 2, lastScan: Date(), status: .ready, message: "正常"))
        ]
    }

    func latestDiagnostics(sourceID: String, limit: Int) async throws -> [DiagnosticListItem] { [] }
}
