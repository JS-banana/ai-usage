import XCTest
import Domain
import Query
@testable import AiUsage

final class AppDataServiceTests: XCTestCase {
    func testQuotaFailureDoesNotBreakUsageSnapshot() async throws {
        let service = AppDataService(
            importCoordinator: ImportRunnerStub(),
            readModelService: SnapshotReaderStub(),
            quotaService: QuotaFetcherStub(error: QuotaServiceError.httpStatus(503)),
            groupQuotaSummaryReadModelService: GroupQuotaSummaryReadModelService(),
            menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
        )

        let snapshot = try await service.refreshAll(trigger: .manual, preferredTabID: nil)

        XCTAssertEqual(snapshot.overview.todayRequests, 6)
        XCTAssertEqual(snapshot.groupQuotaSummary.status, .failed)
        XCTAssertTrue(snapshot.statusMessage.contains("Quota 刷新失败"))
        XCTAssertTrue(snapshot.menuBarSummary.subtitle.contains("请求 6"))
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
            providerTabs: [ProviderTabItem(id: "overview", name: "总览", status: .ready)],
            providerPreferences: [ProviderPreferenceSnapshot(id: "claude-code", name: "Claude", subtitle: "可显示 usage，并支持分组额度配置", supportsQuota: true, isEnabled: true)],
            selectedTabID: "overview",
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

private struct QuotaFetcherStub: GroupQuotaFetching {
    let payload: LaifuyouQuotaPayload?
    let error: (any Error)?

    init(payload: LaifuyouQuotaPayload? = nil, error: (any Error)? = nil) {
        self.payload = payload
        self.error = error
    }

    func fetchIfConfigured(now: Date) async throws -> LaifuyouQuotaPayload? {
        if let error { throw error }
        return payload
    }
}
