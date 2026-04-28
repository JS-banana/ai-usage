import XCTest
import Domain
import Query
@testable import AiUsage

final class AppDataServiceTests: XCTestCase {
    func testResolvedActiveEntitlementFeedsStatusAndMenuBarSummary() async throws {
        let service = AppDataService(
            importCoordinator: ImportRunnerStub(),
            readModelService: SnapshotReaderStub(),
            entitlementService: EntitlementResolverStub(),
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        let snapshot = try await service.refreshAll(trigger: .manual, preferredTabID: nil)

        XCTAssertEqual(snapshot.overview.todayRequests, 6)
        XCTAssertEqual(snapshot.entitlementSummariesByTarget[EntitlementTargetID.overview.storageKey]?.status, .ready)
        XCTAssertTrue(snapshot.statusMessage.contains("第三方套餐额度已更新"))
        XCTAssertTrue(snapshot.menuBarSummary.subtitle.contains("总览"))
        XCTAssertEqual(snapshot.menuBarSummary.glyph.leftRatio, 0.2, accuracy: 0.001)
    }
}

private struct ImportRunnerStub: ImportRunning {
    func runImport(request: ImportRequest) async throws -> ImportResult {
        ImportResult(
            run: ImportRun(id: "run-1", startedAt: request.startedAt, finishedAt: request.startedAt, status: .succeeded, trigger: request.trigger, totalFiles: 0, totalEvents: 0, totalSessions: 0, skippedRecords: 0),
            sourceResults: []
        )
    }
}

private struct SnapshotReaderStub: AppSnapshotReading {
    func makeSnapshot(preferredTabID: String?) async throws -> AppSnapshot {
        AppSnapshot(
            providerTabs: [
                ProviderTabItem(
                    id: EntitlementTargetID.overview.storageKey,
                    name: "总览",
                    status: .ready,
                    branding: ProviderBrandCatalog.branding(for: "overview", fallbackName: "总览"),
                    usageProgress: nil
                )
            ],
            providerPreferences: [ProviderPreferenceSnapshot(id: "claude-code", name: "Claude", subtitle: "控制该来源是否显示在 usage 统计中", isEnabled: true)],
            selectedTabID: EntitlementTargetID.overview.storageKey,
            overview: OverviewPanelSnapshot(
                todayTokens: 1200,
                sevenDayTokens: 4800,
                todayRequests: 6,
                sevenDayRequests: 24,
                cachedTokens: 100,
                activeSources: 1,
                trendPoints: [],
                providerRows: [],
                lastRefresh: Date()
            ),
            panelsByID: [:],
            lastRefresh: Date(),
            statusMessage: "Usage 已刷新"
        )
    }
}

private struct EntitlementResolverStub: EntitlementResolving {
    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        now: Date
    ) async -> [String: EntitlementSummarySnapshot] {
        [
            EntitlementTargetID.overview.storageKey: EntitlementSummarySnapshot(
                targetID: .overview,
                title: "总览套餐",
                message: "第三方套餐额度已更新。",
                updatedAt: now,
                status: .ready,
                sourceKind: .thirdParty,
                provenance: .explicit,
                derivedFromTitle: nil,
                primaryWindow: .init(id: "overview-5h", title: "5h", primaryText: "已用 20%", secondaryText: "1 / 5", footnoteText: "重置 soon", progress: 0.2),
                secondaryWindow: .init(id: "overview-7d", title: "7d", primaryText: "已用 40%", secondaryText: "2 / 5", footnoteText: "重置 later", progress: 0.4)
            )
        ]
    }
}
