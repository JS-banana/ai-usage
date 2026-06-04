import XCTest
import Domain
import Query
@testable import AiUsage

final class AppDataServiceTests: XCTestCase {
    func testResolvedActiveEntitlementFeedsStatusAndMenuBarSummary() async throws {
        let entitlementResolver = EntitlementResolverStub()
        let service = AppDataService(
            importCoordinator: ImportRunnerStub(),
            readModelService: SnapshotReaderStub(),
            entitlementService: entitlementResolver,
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        let snapshot = try await service.refreshAll(trigger: .manual, preferredTabID: nil)

        XCTAssertEqual(snapshot.overview.todayRequests, 6)
        XCTAssertEqual(snapshot.entitlementSummariesByTarget[EntitlementTargetID.overview.storageKey]?.status, .ready)
        XCTAssertTrue(snapshot.statusMessage.contains("第三方套餐额度已更新"))
        XCTAssertTrue(snapshot.menuBarSummary.subtitle.contains("总览"))
        guard case .dualWindows(let leftRatio, let rightRatio, let isDimmed) = snapshot.menuBarSummary.glyph else {
            return XCTFail("Expected dual window glyph")
        }
        XCTAssertEqual(leftRatio, 0.8, accuracy: 0.001)
        XCTAssertEqual(rightRatio, 0.6, accuracy: 0.001)
        XCTAssertFalse(isDimmed)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 1)
    }

    func testRefreshAllPassesTriggerToEntitlementResolver() async throws {
        let entitlementResolver = EntitlementResolverStub()
        let service = AppDataService(
            importCoordinator: ImportRunnerStub(),
            readModelService: SnapshotReaderStub(),
            entitlementService: entitlementResolver,
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        _ = try await service.refreshAll(trigger: .startup, preferredTabID: nil)

        XCTAssertEqual(entitlementResolver.lastTrigger, .startup)
    }

    func testRefreshUsageDoesNotResolveEntitlements() async throws {
        let importRunner = ImportRunnerStub()
        let entitlementResolver = EntitlementResolverStub()
        let service = AppDataService(
            importCoordinator: importRunner,
            readModelService: SnapshotReaderStub(),
            entitlementService: entitlementResolver,
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        let snapshot = try await service.refreshUsage(trigger: .background, preferredTabID: nil)

        XCTAssertEqual(snapshot.overview.todayRequests, 6)
        XCTAssertEqual(snapshot.entitlementSummariesByTarget.count, 0)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 0)
        XCTAssertEqual(importRunner.runCount, 1)
    }

    func testRefreshEntitlementsDoesNotRunUsageImportAndKeepsUsageSnapshot() async throws {
        let importRunner = ImportRunnerStub()
        let entitlementResolver = EntitlementResolverStub()
        let service = AppDataService(
            importCoordinator: importRunner,
            readModelService: SnapshotReaderStub(),
            entitlementService: entitlementResolver,
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )
        let usageSnapshot = try await service.refreshUsage(trigger: .startup, preferredTabID: nil)

        let snapshot = try await service.refreshEntitlements(from: usageSnapshot, preferredTabID: nil)

        XCTAssertEqual(importRunner.runCount, 1)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 1)
        XCTAssertEqual(snapshot.overview.todayRequests, usageSnapshot.overview.todayRequests)
        XCTAssertEqual(snapshot.entitlementSummariesByTarget[EntitlementTargetID.overview.storageKey]?.status, .ready)
    }

    func testRefreshEntitlementsPassesTriggerToResolver() async throws {
        let entitlementResolver = EntitlementResolverStub()
        let service = AppDataService(
            importCoordinator: ImportRunnerStub(),
            readModelService: SnapshotReaderStub(),
            entitlementService: entitlementResolver,
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        _ = try await service.refreshEntitlements(trigger: .background, preferredTabID: nil)

        XCTAssertEqual(entitlementResolver.lastTrigger, .background)
    }
}

private final class ImportRunnerStub: ImportRunning, @unchecked Sendable {
    private(set) var runCount = 0

    func runImport(request: ImportRequest) async throws -> ImportResult {
        runCount += 1
        return ImportResult(
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

private final class EntitlementResolverStub: EntitlementResolving, @unchecked Sendable {
    private(set) var resolveCallCount = 0
    private(set) var lastTrigger: ImportTrigger?

    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        trigger: ImportTrigger,
        now: Date
    ) async -> [String: EntitlementSummarySnapshot] {
        resolveCallCount += 1
        lastTrigger = trigger
        return [
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
