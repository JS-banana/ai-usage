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
        XCTAssertEqual(snapshot.providerTabs.first?.branding.accentToken, .overview)
        XCTAssertNil(snapshot.providerTabs.first?.usageProgress)
        XCTAssertEqual(snapshot.providerTabs.last?.branding.accentToken, .claude)
        XCTAssertEqual(snapshot.providerTabs.last?.usageProgress ?? 0, 1, accuracy: 0.001)
    }

    func testReadModelBuildsUsageProgressFromVisibleProviderRequests() async throws {
        let defaults = UserDefaults(suiteName: "AppReadModelServiceProgressTests")!
        defaults.removePersistentDomain(forName: "AppReadModelServiceProgressTests")

        let service = AppReadModelService(
            sourceRegistry: SourceRegistryStub(),
            dashboardQuery: DashboardQueryStub(),
            sourceHealthQuery: SourceHealthQueryStub(),
            userDefaults: defaults
        )

        let snapshot = try await service.makeSnapshot(preferredTabID: nil)

        let claude = try XCTUnwrap(snapshot.providerTabs.first(where: { $0.id == "claude-code" }))
        let codex = try XCTUnwrap(snapshot.providerTabs.first(where: { $0.id == "codex" }))

        XCTAssertEqual(claude.branding.accentToken, .claude)
        XCTAssertEqual(codex.branding.accentToken, .codex)
        XCTAssertEqual(claude.usageProgress ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(codex.usageProgress ?? 0, 1, accuracy: 0.001)
    }

    func testBrandCatalogProvidesCodexBarResourceMappingsAndFallbackBranding() {
        let claude = ProviderBrandCatalog.branding(for: "claude-code", fallbackName: "Claude")
        let codex = ProviderBrandCatalog.branding(for: "codex", fallbackName: "Codex")
        let gemini = ProviderBrandCatalog.branding(for: "gemini", fallbackName: "Gemini")
        let opencode = ProviderBrandCatalog.branding(for: "opencode", fallbackName: "OpenCode")
        let antigravity = ProviderBrandCatalog.branding(for: "antigravity", fallbackName: "Antigravity")

        XCTAssertEqual(claude.accentToken, .claude)
        XCTAssertEqual(claude.logoResource?.name, "ProviderIcon-claude")
        XCTAssertEqual(codex.accentToken, .codex)
        XCTAssertEqual(codex.logoResource?.name, "ProviderIcon-codex")
        XCTAssertEqual(gemini.accentToken, .gemini)
        XCTAssertEqual(gemini.logoResource?.name, "ProviderIcon-gemini")
        XCTAssertEqual(opencode.accentToken, .opencode)
        XCTAssertEqual(opencode.logoResource?.name, "ProviderIcon-opencode")
        XCTAssertEqual(antigravity.accentToken, .antigravity)
        XCTAssertEqual(antigravity.logoResource?.name, "ProviderIcon-antigravity")
        XCTAssertEqual(claude.logoResource?.fileExtension, "svg")
        XCTAssertEqual(codex.logoResource?.fileExtension, "svg")

        let fallback = ProviderBrandCatalog.branding(for: "unknown-provider", fallbackName: "Antigravity")
        XCTAssertEqual(fallback.accentToken, .generic)

        switch fallback.fallbackIcon {
        case .monogram(let value):
            XCTAssertEqual(value, "A")
        case .symbol:
            XCTFail("Expected fallback monogram for unknown provider")
        }
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
        let metrics = sourceIDs.reduce(
            DashboardMetrics(todayTokens: 0, sevenDayTokens: 0, todayRequests: 0, sevenDayRequests: 0, sessionCount: 0, activeSources: 0)
        ) { partial, sourceID in
            let sourceMetrics = metricsBySourceID[sourceID] ?? DashboardMetrics(todayTokens: 0, sevenDayTokens: 0, todayRequests: 0, sevenDayRequests: 0, sessionCount: 0, activeSources: 0)
            return DashboardMetrics(
                todayTokens: partial.todayTokens + sourceMetrics.todayTokens,
                sevenDayTokens: partial.sevenDayTokens + sourceMetrics.sevenDayTokens,
                todayRequests: partial.todayRequests + sourceMetrics.todayRequests,
                sevenDayRequests: partial.sevenDayRequests + sourceMetrics.sevenDayRequests,
                sessionCount: partial.sessionCount + sourceMetrics.sessionCount,
                activeSources: partial.activeSources + sourceMetrics.activeSources
            )
        }
        return DashboardSummary(metrics: metrics)
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

    private var metricsBySourceID: [String: DashboardMetrics] {
        [
            "claude-code": DashboardMetrics(todayTokens: 100, sevenDayTokens: 700, todayRequests: 1, sevenDayRequests: 4, sessionCount: 1, activeSources: 1),
            "codex": DashboardMetrics(todayTokens: 200, sevenDayTokens: 900, todayRequests: 2, sevenDayRequests: 8, sessionCount: 1, activeSources: 1)
        ]
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
