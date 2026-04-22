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
    var selectedTabID: String?
    var overviewPanel: OverviewPanelSnapshot?
    var providerPanelsByID: [String: ProviderPanelSnapshot] = [:]

    private let dataService: AppDataService

    init(dataService: AppDataService = try! .live()) {
        self.dataService = dataService
    }

    var selectedPanel: ProviderPanelSnapshot? {
        guard let selectedTabID, selectedTabID != "overview" else { return nil }
        return providerPanelsByID[selectedTabID]
    }

    func startIfNeeded() async {
        guard hasBootstrapped == false else { return }
        hasBootstrapped = true
        await refresh(trigger: .startup)
    }

    func refreshOnBecomeActive() async {
        guard lastRefresh != nil else { return }
        await refresh(trigger: .background)
    }

    func refresh(trigger: ImportTrigger = .manual) async {
        guard isLoading == false else { return }
        isLoading = true
        statusMessage = "正在刷新数据…"
        defer { isLoading = false }

        do {
            let snapshot = try await dataService.refreshAll(trigger: trigger, preferredTabID: selectedTabID)
            providerTabs = snapshot.providerTabs
            overviewPanel = snapshot.overview
            providerPanelsByID = snapshot.panelsByID
            selectedTabID = snapshot.selectedTabID
            lastRefresh = snapshot.lastRefresh
            statusMessage = "已完成刷新"
        } catch {
            statusMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    func selectTab(_ tabID: String) {
        selectedTabID = tabID
    }
}
