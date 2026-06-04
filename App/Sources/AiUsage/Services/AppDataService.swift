import Foundation
import Domain
import Ingestion
import Persistence

protocol ImportRunning {
    func runImport(request: ImportRequest) async throws -> ImportResult
}

protocol AppSnapshotReading {
    func makeSnapshot(preferredTabID: String?) async throws -> AppSnapshot
}

protocol EntitlementResolving {
    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        trigger: ImportTrigger,
        now: Date
    ) async -> [String: EntitlementSummarySnapshot]
}

protocol QuotaSnapshotStoring: Sendable {
    func persistQuotaSnapshot(_ snapshot: ProviderQuotaSnapshot) async throws
    func latestQuotaSnapshot(providerID: String, accountID: String) async throws -> ProviderQuotaSnapshot?
}

extension ImportCoordinator: ImportRunning {}
extension AppReadModelService: AppSnapshotReading {}
extension EntitlementResolutionService: EntitlementResolving {}
extension LiveDatabase: QuotaSnapshotStoring {}

actor AppDataService {
    nonisolated(unsafe) private let importCoordinator: any ImportRunning
    nonisolated(unsafe) private let readModelService: any AppSnapshotReading
    nonisolated(unsafe) private let entitlementService: any EntitlementResolving
    private let menuBarSummaryReadModelService: MenuBarSummaryReadModelService

    init(
        importCoordinator: any ImportRunning,
        readModelService: any AppSnapshotReading,
        entitlementService: any EntitlementResolving,
        menuBarSummaryReadModelService: MenuBarSummaryReadModelService
    ) {
        self.importCoordinator = importCoordinator
        self.readModelService = readModelService
        self.entitlementService = entitlementService
        self.menuBarSummaryReadModelService = menuBarSummaryReadModelService
    }

    func refreshAll(trigger: ImportTrigger, preferredTabID: String?) async throws -> AppSnapshot {
        let usageSnapshot = try await refreshUsage(trigger: trigger, preferredTabID: preferredTabID)
        return try await refreshEntitlements(from: usageSnapshot, trigger: trigger, preferredTabID: preferredTabID)
    }

    func refreshUsage(trigger: ImportTrigger, preferredTabID: String?) async throws -> AppSnapshot {
        _ = try await importCoordinator.runImport(request: ImportRequest(trigger: trigger))
        var snapshot = try await readModelService.makeSnapshot(preferredTabID: preferredTabID)
        snapshot.statusMessage = "Usage 已刷新"
        snapshot.menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            activeTargetID: snapshot.selectedTabID,
            overview: snapshot.overview,
            entitlementsByTarget: snapshot.entitlementSummariesByTarget
        )
        return snapshot
    }

    func refreshEntitlements(from existingSnapshot: AppSnapshot, trigger: ImportTrigger = .manual, preferredTabID: String?) async throws -> AppSnapshot {
        var snapshot = existingSnapshot
        let descriptors = EntitlementPreferences.descriptorTargets(providerPreferences: snapshot.providerPreferences)
        let visibleProviderIDs = Set(snapshot.providerTabs.map(\.id).filter { $0 != EntitlementTargetID.overview.storageKey })
        snapshot.entitlementSummariesByTarget = await entitlementService.resolveSummaries(
            descriptors: descriptors,
            visibleProviderIDs: visibleProviderIDs,
            trigger: trigger,
            now: Date()
        )
        snapshot.menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            activeTargetID: snapshot.selectedTabID,
            overview: snapshot.overview,
            entitlementsByTarget: snapshot.entitlementSummariesByTarget
        )
        if let activeSummary = snapshot.entitlementSummariesByTarget[snapshot.selectedTabID] {
            snapshot.statusMessage = "Usage 已刷新 · \(activeSummary.message)"
        }
        return snapshot
    }

    func refreshEntitlements(trigger: ImportTrigger = .manual, preferredTabID: String?) async throws -> AppSnapshot {
        let snapshot = try await readModelService.makeSnapshot(preferredTabID: preferredTabID)
        return try await refreshEntitlements(from: snapshot, trigger: trigger, preferredTabID: preferredTabID)
    }
}
