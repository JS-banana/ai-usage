import Foundation
import Observation
import Domain
import Query

enum RefreshDomainState: Hashable, Sendable {
    case idle
    case refreshing
    case failed(String)
}

struct RefreshPolicy: Hashable, Sendable {
    let usageTTL: TimeInterval
    let entitlementTTL: TimeInterval
    let schedulerTick: TimeInterval

    init(usageTTL: TimeInterval = 600, entitlementTTL: TimeInterval = 1800, schedulerTick: TimeInterval = 60) {
        self.usageTTL = usageTTL
        self.entitlementTTL = entitlementTTL
        self.schedulerTick = schedulerTick
    }
}

@MainActor
@Observable
final class AppState {
    var hasBootstrapped = false
    var isLoading = false
    var lastRefresh: Date?
    var lastUsageRefresh: Date?
    var lastEntitlementRefresh: Date?
    var usageRefreshState: RefreshDomainState = .idle
    var entitlementRefreshState: RefreshDomainState = .idle
    var statusMessage = "准备就绪"
    var providerTabs: [ProviderTabItem] = []
    var providerPreferences: [ProviderPreferenceSnapshot] = []
    var entitlementTargets: [EntitlementTargetDescriptor] = []
    var selectedTabID: String?
    var overviewPanel: OverviewPanelSnapshot?
    var providerPanelsByID: [String: ProviderPanelSnapshot] = [:]
    var entitlementSummariesByTarget: [String: EntitlementSummarySnapshot] = [:]
    var completedMiMoLoginSequence = 0
    var miMoLoginSessionID = UUID()
    var menuBarSummary: MenuBarSummarySnapshot = .init(
        title: "AiUsage",
        subtitle: "暂无数据",
        status: .empty,
        glyph: .empty
    )

    private let dataService: AppDataService?
    private let bootstrapErrorMessage: String?
    private let refreshPolicy: RefreshPolicy
    private let menuBarSummaryReadModelService = MenuBarSummaryReadModelService()
    private var refreshSequence = 0
    private var usageRefreshSequence = 0
    private var entitlementRefreshSequence = 0
    private var autoRefreshTask: Task<Void, Never>?

    var isAutoRefreshActive: Bool { autoRefreshTask != nil }
    var isEntitlementRefreshInProgress: Bool { isRefreshingEntitlements }

    private var isRefreshingUsage: Bool {
        if case .refreshing = usageRefreshState { return true }
        return false
    }

    private var isRefreshingEntitlements: Bool {
        if case .refreshing = entitlementRefreshState { return true }
        return false
    }

    init(dataService: AppDataService, refreshPolicy: RefreshPolicy = RefreshPolicy()) {
        self.dataService = dataService
        self.bootstrapErrorMessage = nil
        self.refreshPolicy = refreshPolicy
    }

    init(bootstrapError: any Error, refreshPolicy: RefreshPolicy = RefreshPolicy()) {
        let message = "启动失败：\(bootstrapError.localizedDescription)"
        self.dataService = nil
        self.bootstrapErrorMessage = message
        self.refreshPolicy = refreshPolicy
        self.statusMessage = message
    }

    var selectedPanel: ProviderPanelSnapshot? {
        guard let selectedTabID, selectedTabID != EntitlementTargetID.overview.storageKey else { return nil }
        return providerPanelsByID[selectedTabID]
    }

    var activeEntitlementSummary: EntitlementSummarySnapshot? {
        entitlementSummariesByTarget[selectedTabID ?? EntitlementTargetID.overview.storageKey]
    }

    var quotaGroups: [QuotaVendorGroupSnapshot] {
        QuotaAccountReadModel.makeGroups(entitlementsByTarget: entitlementSummariesByTarget)
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
        // Opening or activating the app must not be a refresh trigger.
    }

    @discardableResult
    func refresh(trigger: ImportTrigger = .manual) async -> Bool {
        guard isRefreshingUsage == false, isRefreshingEntitlements == false else { return false }
        guard let dataService else {
            statusMessage = bootstrapErrorMessage ?? "刷新失败：数据服务未初始化"
            return false
        }
        let previousStatusMessage = statusMessage
        refreshSequence += 1
        let refreshID = refreshSequence
        isLoading = true
        usageRefreshState = .refreshing
        entitlementRefreshState = .refreshing
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
            entitlementTargets = snapshot.entitlementTargets
            overviewPanel = snapshot.overview
            providerPanelsByID = snapshot.panelsByID
            entitlementSummariesByTarget = snapshot.entitlementSummariesByTarget
            selectedTabID = snapshot.selectedTabID
            menuBarSummary = snapshot.menuBarSummary
            lastRefresh = snapshot.lastRefresh
            lastUsageRefresh = snapshot.lastRefresh
            lastEntitlementRefresh = snapshot.lastRefresh
            usageRefreshState = .idle
            entitlementRefreshState = .idle
            statusMessage = snapshot.statusMessage
            return true
        } catch is CancellationError {
            statusMessage = previousStatusMessage
            usageRefreshState = .idle
            entitlementRefreshState = .idle
            return false
        } catch {
            let message = error.localizedDescription
            usageRefreshState = .failed(message)
            entitlementRefreshState = .failed(message)
            statusMessage = "刷新失败：\(message)"
            return false
        }
    }

    @discardableResult
    func refreshUsage(trigger: ImportTrigger = .manual) async -> Bool {
        guard isRefreshingUsage == false else { return false }
        guard let dataService else {
            statusMessage = bootstrapErrorMessage ?? "刷新失败：数据服务未初始化"
            return false
        }
        let previousStatusMessage = statusMessage
        usageRefreshSequence += 1
        let refreshID = usageRefreshSequence
        isLoading = true
        usageRefreshState = .refreshing
        statusMessage = "正在刷新 Usage…"
        defer {
            if usageRefreshSequence == refreshID {
                isLoading = isRefreshingEntitlements
            }
        }

        do {
            let snapshot = try await dataService.refreshUsage(trigger: trigger, preferredTabID: selectedTabID)
            guard usageRefreshSequence == refreshID else { return false }
            applyUsageSnapshot(snapshot)
            lastRefresh = snapshot.lastRefresh
            lastUsageRefresh = snapshot.lastRefresh
            usageRefreshState = .idle
            statusMessage = snapshot.statusMessage
            return true
        } catch is CancellationError {
            statusMessage = previousStatusMessage
            usageRefreshState = .idle
            return false
        } catch {
            let message = error.localizedDescription
            usageRefreshState = .failed(message)
            statusMessage = "Usage 刷新失败：\(message)"
            return false
        }
    }

    @discardableResult
    func refreshEntitlements(trigger: ImportTrigger = .manual) async -> Bool {
        guard isRefreshingEntitlements == false else { return false }
        guard let dataService else {
            statusMessage = bootstrapErrorMessage ?? "刷新失败：数据服务未初始化"
            return false
        }
        let previousStatusMessage = statusMessage
        entitlementRefreshSequence += 1
        let refreshID = entitlementRefreshSequence
        isLoading = true
        entitlementRefreshState = .refreshing
        statusMessage = "正在刷新额度…"
        defer {
            if entitlementRefreshSequence == refreshID {
                isLoading = isRefreshingUsage
            }
        }

        do {
            let hasUsageSnapshot = overviewPanel != nil
            let baseSnapshot: AppSnapshot
            if hasUsageSnapshot, let overviewPanel {
                baseSnapshot = AppSnapshot(
                    providerTabs: providerTabs,
                    providerPreferences: providerPreferences,
                    entitlementTargets: entitlementTargets,
                    selectedTabID: selectedTabID ?? EntitlementTargetID.overview.storageKey,
                    overview: overviewPanel,
                    panelsByID: providerPanelsByID,
                    lastRefresh: lastUsageRefresh ?? lastRefresh ?? Date(),
                    entitlementSummariesByTarget: entitlementSummariesByTarget,
                    menuBarSummary: menuBarSummary,
                    statusMessage: statusMessage
                )
            } else {
                baseSnapshot = try await dataService.refreshEntitlements(trigger: trigger, preferredTabID: selectedTabID)
                applyUsageSnapshot(baseSnapshot)
            }
            let snapshot = hasUsageSnapshot == false
                ? baseSnapshot
                : try await dataService.refreshEntitlements(from: baseSnapshot, trigger: trigger, preferredTabID: selectedTabID)
            guard entitlementRefreshSequence == refreshID else { return false }
            applyEntitlementSnapshot(snapshot)
            lastEntitlementRefresh = Date()
            entitlementRefreshState = .idle
            statusMessage = snapshot.statusMessage
            isLoading = isRefreshingUsage
            return true
        } catch is CancellationError {
            statusMessage = previousStatusMessage
            entitlementRefreshState = .idle
            return false
        } catch {
            let message = error.localizedDescription
            entitlementRefreshState = .failed(message)
            statusMessage = "额度刷新失败：\(message)"
            return false
        }
    }

    @discardableResult
    func refreshCurrentEntitlement() async -> Bool {
        await refreshEntitlements(trigger: .manual)
    }

    func refreshIfStale(now: Date = Date()) async {
        if shouldRefresh(lastRefresh: lastUsageRefresh, ttl: refreshPolicy.usageTTL, now: now) {
            _ = await refreshUsage(trigger: .background)
        }
        if shouldRefresh(lastRefresh: lastEntitlementRefresh, ttl: refreshPolicy.entitlementTTL, now: now) {
            _ = await refreshEntitlements(trigger: .background)
        }
    }

    func selectTab(_ tabID: String) {
        selectedTabID = tabID
        refreshMenuBarSummary()
    }

    func setProviderEnabled(_ providerID: String, enabled: Bool) {
        AppPreferences.setSourceEnabled(enabled, sourceID: providerID)
        if enabled == false, selectedTabID == providerID {
            selectedTabID = EntitlementTargetID.overview.storageKey
        }
        refreshMenuBarSummary()
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

    func prepareMiMoLoginSession() {
        miMoLoginSessionID = UUID()
    }

    func startAutoRefresh(intervalSeconds: TimeInterval? = nil) {
        guard autoRefreshTask == nil else { return }
        let tick = intervalSeconds ?? refreshPolicy.schedulerTick
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(tick))
                guard !Task.isCancelled else { break }
                await self?.refreshIfStale()
            }
        }
    }

    func cancelAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func shouldRefresh(lastRefresh: Date?, ttl: TimeInterval, now: Date) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= ttl
    }

    private func applyUsageSnapshot(_ snapshot: AppSnapshot) {
        providerTabs = snapshot.providerTabs
        providerPreferences = snapshot.providerPreferences
        entitlementTargets = snapshot.entitlementTargets
        overviewPanel = snapshot.overview
        providerPanelsByID = snapshot.panelsByID
        selectedTabID = snapshot.selectedTabID
        refreshMenuBarSummary()
    }

    private func applyEntitlementSnapshot(_ snapshot: AppSnapshot) {
        entitlementSummariesByTarget = snapshot.entitlementSummariesByTarget
        menuBarSummary = snapshot.menuBarSummary
    }

    private func refreshMenuBarSummary() {
        menuBarSummary = menuBarSummaryReadModelService.makeSummary(
            targetPreference: .auto,
            overview: overviewPanel,
            entitlementsByTarget: entitlementSummariesByTarget
        )
    }
}
