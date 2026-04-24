import Foundation
import Domain
import Ingestion

protocol ImportRunning {
    func runImport(request: ImportRequest) async throws -> ImportResult
}

protocol AppSnapshotReading {
    func makeSnapshot(preferredTabID: String?) async throws -> AppSnapshot
}

protocol GroupQuotaFetching {
    func fetchIfConfigured(now: Date) async throws -> LaifuyouQuotaPayload?
}

extension ImportCoordinator: ImportRunning {}
extension AppReadModelService: AppSnapshotReading {}
extension LaifuyouQuotaService: GroupQuotaFetching {}

actor AppDataService {
    nonisolated(unsafe) private let importCoordinator: any ImportRunning
    nonisolated(unsafe) private let readModelService: any AppSnapshotReading
    nonisolated(unsafe) private let quotaService: any GroupQuotaFetching
    private let groupQuotaSummaryReadModelService: GroupQuotaSummaryReadModelService
    private let menuBarSummaryReadModelService: MenuBarSummaryReadModelService

    init(
        importCoordinator: any ImportRunning,
        readModelService: any AppSnapshotReading,
        quotaService: any GroupQuotaFetching,
        groupQuotaSummaryReadModelService: GroupQuotaSummaryReadModelService,
        menuBarSummaryReadModelService: MenuBarSummaryReadModelService
    ) {
        self.importCoordinator = importCoordinator
        self.readModelService = readModelService
        self.quotaService = quotaService
        self.groupQuotaSummaryReadModelService = groupQuotaSummaryReadModelService
        self.menuBarSummaryReadModelService = menuBarSummaryReadModelService
    }

    func refreshAll(trigger: ImportTrigger, preferredTabID: String?) async throws -> AppSnapshot {
        _ = try await importCoordinator.runImport(request: ImportRequest(trigger: trigger))
        var snapshot = try await readModelService.makeSnapshot(preferredTabID: preferredTabID)

        do {
            if let quotaPayload = try await quotaService.fetchIfConfigured(now: Date()) {
                snapshot.groupQuotaSummary = groupQuotaSummaryReadModelService.makeSnapshot(from: quotaPayload)
                snapshot.statusMessage = quotaPayload.isStale
                    ? "Usage 已刷新 · 分组额度数据偏旧"
                    : "Usage 已刷新 · 分组额度已更新"
            } else {
                snapshot.groupQuotaSummary = groupQuotaSummaryReadModelService.makeUnconfiguredSnapshot()
                snapshot.statusMessage = "Usage 已刷新 · 分组额度未配置"
            }
        } catch {
            snapshot.groupQuotaSummary = groupQuotaSummaryReadModelService.makeFailureSnapshot(error: error)
            snapshot.statusMessage = "Usage 已刷新 · Quota 刷新失败：\(error.localizedDescription)"
        }

        snapshot.menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            overview: snapshot.overview,
            groupQuotaSummary: snapshot.groupQuotaSummary
        )
        return snapshot
    }
}
