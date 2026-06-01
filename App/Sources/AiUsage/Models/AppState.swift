import Foundation
import Observation
import Domain
import Query

@MainActor
@Observable
final class AppState {
    var hasBootstrapped = false
    var isLoading = false
    var lastRefresh: Date?
    var statusMessage = "准备就绪"
    var providerTabs: [ProviderTabItem] = []
    var providerPreferences: [ProviderPreferenceSnapshot] = []
    var selectedTabID: String?
    var overviewPanel: OverviewPanelSnapshot?
    var providerPanelsByID: [String: ProviderPanelSnapshot] = [:]
    var entitlementSummariesByTarget: [String: EntitlementSummarySnapshot] = [:]
    var completedMiMoLoginSequence = 0
    var menuBarSummary: MenuBarSummarySnapshot = .init(
        title: "AiUsage",
        subtitle: "暂无数据",
        status: .empty,
        glyph: .empty
    )

    private let dataService: AppDataService?
    private let bootstrapErrorMessage: String?
    private let menuBarSummaryReadModelService = MenuBarSummaryReadModelService()
    private var refreshSequence = 0
    private var autoRefreshTask: Task<Void, Never>?

    var isAutoRefreshActive: Bool { autoRefreshTask != nil }

    init(dataService: AppDataService) {
        self.dataService = dataService
        self.bootstrapErrorMessage = nil
    }

    init(bootstrapError: any Error) {
        let message = "启动失败：\(bootstrapError.localizedDescription)"
        self.dataService = nil
        self.bootstrapErrorMessage = message
        self.statusMessage = message
    }

    var selectedPanel: ProviderPanelSnapshot? {
        guard let selectedTabID, selectedTabID != EntitlementTargetID.overview.storageKey else { return nil }
        return providerPanelsByID[selectedTabID]
    }

    var activeEntitlementSummary: EntitlementSummarySnapshot? {
        entitlementSummariesByTarget[selectedTabID ?? EntitlementTargetID.overview.storageKey]
    }

    func startIfNeeded() async {
        guard hasBootstrapped == false else { return }
        guard dataService != nil else {
            hasBootstrapped = true
            return
        }
        if await refresh(trigger: .startup) {
            hasBootstrapped = true
        }
    }

    func refreshOnBecomeActive() async {
        guard lastRefresh != nil else { return }
        await refresh(trigger: .background)
    }

    @discardableResult
    func refresh(trigger: ImportTrigger = .manual) async -> Bool {
        guard isLoading == false else { return false }
        guard let dataService else {
            statusMessage = bootstrapErrorMessage ?? "刷新失败：数据服务未初始化"
            return false
        }
        let previousStatusMessage = statusMessage
        refreshSequence += 1
        let refreshID = refreshSequence
        isLoading = true
        statusMessage = "正在刷新数据…"
        defer {
            if refreshSequence == refreshID {
                isLoading = false
            }
        }

        do {
            let snapshot = try await withTaskCancellationHandler {
                try await dataService.refreshAll(trigger: trigger, preferredTabID: selectedTabID)
            } onCancel: { [weak self, previousStatusMessage, refreshID] in
                Task { @MainActor in
                    guard let self, self.refreshSequence == refreshID else { return }
                    self.refreshSequence += 1
                    self.statusMessage = previousStatusMessage
                    self.isLoading = false
                }
            }
            guard refreshSequence == refreshID else { return false }
            providerTabs = snapshot.providerTabs
            providerPreferences = snapshot.providerPreferences
            overviewPanel = snapshot.overview
            providerPanelsByID = snapshot.panelsByID
            entitlementSummariesByTarget = snapshot.entitlementSummariesByTarget
            selectedTabID = snapshot.selectedTabID
            menuBarSummary = snapshot.menuBarSummary
            lastRefresh = snapshot.lastRefresh
            statusMessage = snapshot.statusMessage
            return true
        } catch is CancellationError {
            statusMessage = previousStatusMessage
            return false
        } catch {
            statusMessage = "刷新失败：\(error.localizedDescription)"
            return false
        }
    }

    func selectTab(_ tabID: String) {
        selectedTabID = tabID
        menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            activeTargetID: tabID,
            overview: overviewPanel,
            entitlementsByTarget: entitlementSummariesByTarget
        )
    }

    func setProviderEnabled(_ providerID: String, enabled: Bool) {
        AppPreferences.setSourceEnabled(enabled, sourceID: providerID)
        if enabled == false, selectedTabID == providerID {
            selectedTabID = EntitlementTargetID.overview.storageKey
        }
        menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            activeTargetID: selectedTabID,
            overview: overviewPanel,
            entitlementsByTarget: entitlementSummariesByTarget
        )
        Task {
            await refresh(trigger: .manual)
        }
    }

    func isProviderEnabled(_ providerID: String) -> Bool {
        providerPreferences.first(where: { $0.id == providerID })?.isEnabled ?? true
    }

    func markMiMoLoginCompleted() {
        completedMiMoLoginSequence += 1
    }

    func startAutoRefresh(intervalSeconds: TimeInterval = 1800) {
        cancelAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled else { break }
                await self?.refresh(trigger: .background)
            }
        }
    }

    func cancelAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
