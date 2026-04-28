import Foundation
import Domain
import Ingestion
import ProviderKit
import Query

struct OverviewProviderRow: Identifiable, Sendable {
    let id: String
    let name: String
    let todayTokens: Int
    let todayRequests: Int
    let status: SourceStatus
}

struct OverviewPanelSnapshot: Sendable {
    let todayTokens: Int
    let sevenDayTokens: Int
    let todayRequests: Int
    let sevenDayRequests: Int
    let cachedTokens: Int
    let activeSources: Int
    let trendPoints: [BucketPoint]
    let providerRows: [OverviewProviderRow]
    let lastRefresh: Date
}

struct AppSnapshot: Sendable {
    let providerTabs: [ProviderTabItem]
    let providerPreferences: [ProviderPreferenceSnapshot]
    let selectedTabID: String
    let overview: OverviewPanelSnapshot
    let panelsByID: [String: ProviderPanelSnapshot]
    let lastRefresh: Date
    var entitlementSummariesByTarget: [String: EntitlementSummarySnapshot] = [:]
    var menuBarSummary: MenuBarSummarySnapshot = .init(
        title: "AiUsage",
        subtitle: "暂无数据",
        status: .empty,
        glyph: .empty
    )
    var statusMessage: String = "准备就绪"
}

struct AppReadModelService {
    private let sourceRegistry: SourceRegistry
    private let dashboardQuery: DashboardQueryServing
    private let sourceHealthQuery: SourceHealthQueryServing
    private let userDefaults: UserDefaults

    init(
        sourceRegistry: SourceRegistry,
        dashboardQuery: DashboardQueryServing,
        sourceHealthQuery: SourceHealthQueryServing,
        userDefaults: UserDefaults = .standard
    ) {
        self.sourceRegistry = sourceRegistry
        self.dashboardQuery = dashboardQuery
        self.sourceHealthQuery = sourceHealthQuery
        self.userDefaults = userDefaults
    }

    func makeSnapshot(preferredTabID: String?) async throws -> AppSnapshot {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let now = Date()
        let allDescriptors = sourceRegistry.providerDescriptors()
        let providerPreferences = allDescriptors.map { AppPreferences.preferenceSnapshot(for: $0, userDefaults: userDefaults) }
        let descriptors = allDescriptors.filter { AppPreferences.isSourceEnabled($0.id, userDefaults: userDefaults) }

        if descriptors.isEmpty {
            let overview = OverviewPanelSnapshot(
                todayTokens: 0,
                sevenDayTokens: 0,
                todayRequests: 0,
                sevenDayRequests: 0,
                cachedTokens: 0,
                activeSources: 0,
                trendPoints: [],
                providerRows: [],
                lastRefresh: now
            )
            return AppSnapshot(
                providerTabs: [
                    ProviderTabItem(
                        id: "overview",
                        name: "总览",
                        status: .unavailable,
                        branding: ProviderBrandCatalog.branding(for: "overview", fallbackName: "总览"),
                        usageProgress: nil
                    )
                ],
                providerPreferences: providerPreferences,
                selectedTabID: "overview",
                overview: overview,
                panelsByID: [:],
                lastRefresh: now,
                statusMessage: "请先在账号与配置中启用至少一个来源"
            )
        }

        let sourceIDs = descriptors.map(\.id)
        let startOfToday = calendar.startOfDay(for: now)
        let currentWeek = currentWeekWindow(containing: now, calendar: calendar)
        let todayRange = DateRange(start: startOfToday, end: now)
        let currentWeekRange = DateRange(start: currentWeek.start, end: currentWeek.end)
        let dashboardQuery = self.dashboardQuery
        let sourceHealthQuery = self.sourceHealthQuery

        async let todaySummary = dashboardQuery.summary(range: todayRange, sourceIDs: sourceIDs)
        async let currentWeekSummary = dashboardQuery.summary(range: currentWeekRange, sourceIDs: sourceIDs)
        async let overallTrend = dashboardQuery.trend(range: currentWeekRange, granularity: .daily, sourceIDs: sourceIDs)
        async let overallCachedBreakdown = dashboardQuery.cachedBreakdownBySource(range: todayRange, limit: 20)
        async let sourceOverview = sourceHealthQuery.sourceOverview()

        let allSourceHealth = try await sourceOverview
        let sourceHealth = Dictionary(uniqueKeysWithValues: allSourceHealth.filter { sourceIDs.contains($0.id) }.map { ($0.id, $0.health) })
        let cachedBreakdownByID = Dictionary(uniqueKeysWithValues: try await overallCachedBreakdown.filter { sourceIDs.contains($0.id) }.map { ($0.id, $0.value) })

        var panelsByID: [String: ProviderPanelSnapshot] = [:]
        for descriptor in descriptors {
            let sourceID = descriptor.id
            let todaySummary = try await dashboardQuery.summary(range: todayRange, sourceIDs: [sourceID])
            let currentWeekSummary = try await dashboardQuery.summary(range: currentWeekRange, sourceIDs: [sourceID])
            let trendPoints = normalizeWeekTrend(
                try await dashboardQuery.trend(range: currentWeekRange, granularity: .daily, sourceIDs: [sourceID]),
                week: currentWeek,
                calendar: calendar
            )
            let health = sourceHealth[sourceID] ?? SourceHealth(
                id: sourceID,
                name: descriptor.displayName,
                discoveredFiles: 0,
                importedSessions: 0,
                lastScan: nil,
                status: .unavailable,
                message: "暂无数据"
            )

            panelsByID[sourceID] = ProviderPanelSnapshot(
                id: sourceID,
                name: descriptor.displayName,
                todayTokens: todaySummary.metrics.todayTokens,
                sevenDayTokens: currentWeekSummary.metrics.todayTokens,
                todayRequests: todaySummary.metrics.todayRequests,
                sevenDayRequests: currentWeekSummary.metrics.todayRequests,
                cachedTokens: cachedBreakdownByID[sourceID] ?? 0,
                status: health.status,
                message: health.message,
                trendPoints: trendPoints,
                importedSessions: health.importedSessions,
                lastRefresh: health.lastScan
            )
        }

        let providerTabs = makeProviderTabs(
            descriptors: descriptors,
            sourceHealth: sourceHealth,
            panelsByID: panelsByID
        )

        let todayMetrics = try await todaySummary.metrics
        let currentWeekMetrics = try await currentWeekSummary.metrics
        let overview = OverviewPanelSnapshot(
            todayTokens: todayMetrics.todayTokens,
            sevenDayTokens: currentWeekMetrics.todayTokens,
            todayRequests: todayMetrics.todayRequests,
            sevenDayRequests: currentWeekMetrics.todayRequests,
            cachedTokens: cachedBreakdownByID.values.reduce(0, +),
            activeSources: todayMetrics.activeSources,
            trendPoints: normalizeWeekTrend(try await overallTrend, week: currentWeek, calendar: calendar),
            providerRows: descriptors.map { descriptor in
                let panel = panelsByID[descriptor.id]
                return OverviewProviderRow(
                    id: descriptor.id,
                    name: descriptor.displayName,
                    todayTokens: panel?.todayTokens ?? 0,
                    todayRequests: panel?.todayRequests ?? 0,
                    status: sourceHealth[descriptor.id]?.status ?? .unavailable
                )
            },
            lastRefresh: now
        )

        return AppSnapshot(
            providerTabs: providerTabs,
            providerPreferences: providerPreferences,
            selectedTabID: resolvedSelectedTabID(
                preferredTabID: preferredTabID,
                providerTabs: providerTabs,
                panelsByID: panelsByID,
                overview: overview
            ),
            overview: overview,
            panelsByID: panelsByID,
            lastRefresh: now,
            statusMessage: "Usage 已刷新"
        )
    }

    private func currentWeekWindow(containing date: Date, calendar: Calendar) -> WeekWindow {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? date
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { calendar.startOfDay(for: $0) }
        return WeekWindow(start: start, end: end, days: days)
    }

    private func normalizeWeekTrend(_ points: [BucketPoint], week: WeekWindow, calendar: Calendar) -> [BucketPoint] {
        let valuesByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.value) })
        let idFormatter = DateFormatter()
        idFormatter.calendar = calendar
        idFormatter.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEE"

        return week.days.map { day in
            let id = idFormatter.string(from: day)
            let label = weekdayFormatter.string(from: day)
            return BucketPoint(id: id, label: label, value: valuesByID[id] ?? 0)
        }
    }

    private func resolvedSelectedTabID(
        preferredTabID: String?,
        providerTabs: [ProviderTabItem],
        panelsByID: [String: ProviderPanelSnapshot],
        overview: OverviewPanelSnapshot
    ) -> String {
        if let preferredTabID, providerTabs.contains(where: { $0.id == preferredTabID }) {
            return preferredTabID
        }
        return overview.todayTokens > 0 ? "overview" : (providerTabs.first(where: { ($0.id != "overview") && ((panelsByID[$0.id]?.todayTokens ?? 0) > 0) })?.id ?? "overview")
    }

    private func makeProviderTabs(
        descriptors: [ProviderDescriptor],
        sourceHealth: [String: SourceHealth],
        panelsByID: [String: ProviderPanelSnapshot]
    ) -> [ProviderTabItem] {
        let maxRequests = max(1, descriptors.compactMap { panelsByID[$0.id]?.sevenDayRequests }.max() ?? 0)
        let overviewTab = ProviderTabItem(
            id: "overview",
            name: "总览",
            status: .ready,
            branding: ProviderBrandCatalog.branding(for: "overview", fallbackName: "总览"),
            usageProgress: nil
        )

        let providerTabs = descriptors.map { descriptor in
            let weeklyRequests = panelsByID[descriptor.id]?.sevenDayRequests ?? 0
            return ProviderTabItem(
                id: descriptor.id,
                name: descriptor.displayName,
                status: sourceHealth[descriptor.id]?.status ?? .unavailable,
                branding: ProviderBrandCatalog.branding(for: descriptor.id, fallbackName: descriptor.displayName),
                usageProgress: Double(weeklyRequests) / Double(maxRequests)
            )
        }

        return [overviewTab] + providerTabs
    }
}

private struct WeekWindow {
    let start: Date
    let end: Date
    let days: [Date]
}
