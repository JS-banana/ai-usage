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
    var menuBarSummary: MenuBarSummarySnapshot = .init(
        title: "AiUsage",
        subtitle: "暂无数据",
        status: .empty,
        glyph: .empty
    )

    private let dataService: AppDataService?
    private let bootstrapErrorMessage: String?
    private let menuBarSummaryReadModelService = MenuBarSummaryReadModelService()

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
        hasBootstrapped = true
        guard dataService != nil else { return }
        await refresh(trigger: .startup)
    }

    func refreshOnBecomeActive() async {
        guard lastRefresh != nil else { return }
        await refresh(trigger: .background)
    }

    func refresh(trigger: ImportTrigger = .manual) async {
        guard isLoading == false else { return }
        guard let dataService else {
            statusMessage = bootstrapErrorMessage ?? "刷新失败：数据服务未初始化"
            return
        }
        isLoading = true
        statusMessage = "正在刷新数据…"
        defer { isLoading = false }

        do {
            let snapshot = try await dataService.refreshAll(trigger: trigger, preferredTabID: selectedTabID)
            providerTabs = snapshot.providerTabs
            providerPreferences = snapshot.providerPreferences
            overviewPanel = snapshot.overview
            providerPanelsByID = snapshot.panelsByID
            entitlementSummariesByTarget = snapshot.entitlementSummariesByTarget
            selectedTabID = snapshot.selectedTabID
            menuBarSummary = snapshot.menuBarSummary
            lastRefresh = snapshot.lastRefresh
            statusMessage = snapshot.statusMessage
        } catch {
            statusMessage = "刷新失败：\(error.localizedDescription)"
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
}
