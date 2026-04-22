import Foundation
import Domain
import Ingestion
import Persistence
import Query

struct ProviderTabItem: Identifiable, Sendable {
    let id: String
    let name: String
    let status: SourceStatus
}

struct OverviewProviderRow: Identifiable, Sendable {
    let id: String
    let name: String
    let todayTokens: Int
    let status: SourceStatus
}

struct OverviewPanelSnapshot: Sendable {
    let todayTokens: Int
    let sevenDayTokens: Int
    let cachedTokens: Int
    let activeSources: Int
    let trendPoints: [BucketPoint]
    let providerRows: [OverviewProviderRow]
    let lastRefresh: Date
}

struct AppSnapshot: Sendable {
    let providerTabs: [ProviderTabItem]
    let selectedTabID: String
    let overview: OverviewPanelSnapshot
    let panelsByID: [String: ProviderPanelSnapshot]
    let lastRefresh: Date
}

actor AppDataService {
    private let sourceRegistry: SourceRegistry
    private let importCoordinator: ImportCoordinator
    private let dashboardQuery: DashboardQueryServing
    private let sourceHealthQuery: SourceHealthQueryServing

    init(
        sourceRegistry: SourceRegistry,
        importCoordinator: ImportCoordinator,
        dashboardQuery: DashboardQueryServing,
        sourceHealthQuery: SourceHealthQueryServing
    ) {
        self.sourceRegistry = sourceRegistry
        self.importCoordinator = importCoordinator
        self.dashboardQuery = dashboardQuery
        self.sourceHealthQuery = sourceHealthQuery
    }

    static func live() throws -> AppDataService {
        let database = try LiveDatabase(configuration: try LiveDatabase.appSupportConfiguration())
        let sourceRegistry = StaticSourceRegistry()
        let dashboardQuery = LiveDashboardQueryService(analytics: database)
        let sourceHealthQuery = LiveSourceHealthQueryService(analytics: database)
        let coordinator = ImportCoordinator(
            registry: sourceRegistry,
            discovery: DefaultSourceDiscovery(),
            deduplicator: NoOpDeduplicator(),
            persistence: database
        )
        return AppDataService(
            sourceRegistry: sourceRegistry,
            importCoordinator: coordinator,
            dashboardQuery: dashboardQuery,
            sourceHealthQuery: sourceHealthQuery
        )
    }

    func refreshAll(trigger: ImportTrigger, preferredTabID: String?) async throws -> AppSnapshot {
        _ = try await importCoordinator.runImport(request: ImportRequest(trigger: trigger))

        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let currentWeek = currentWeekWindow(containing: now, calendar: calendar)

        let todayRange = DateRange(start: startOfToday, end: now)
        let currentWeekRange = DateRange(start: currentWeek.start, end: currentWeek.end)

        async let todaySummary = dashboardQuery.summary(range: todayRange)
        async let currentWeekSummary = dashboardQuery.summary(range: currentWeekRange)
        async let overallTrend = dashboardQuery.trend(range: currentWeekRange, granularity: .daily)
        async let overallCachedBreakdown = dashboardQuery.cachedBreakdownBySource(range: todayRange, limit: 20)
        async let sourceOverview = sourceHealthQuery.sourceOverview()

        let sourceHealth = Dictionary(uniqueKeysWithValues: try await sourceOverview.map { ($0.id, $0.health) })
        let descriptors = sourceRegistry.allSources()

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
            let cachedValue = try await dashboardQuery.cachedBreakdownBySource(range: todayRange, limit: 20)
                .first(where: { $0.id == sourceID })?.value ?? 0
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
                name: shortProviderName(for: descriptor),
                todayTokens: todaySummary.metrics.todayTokens,
                sevenDayTokens: currentWeekSummary.metrics.todayTokens,
                cachedTokens: cachedValue,
                status: health.status,
                message: health.message,
                trendPoints: trendPoints,
                importedSessions: health.importedSessions,
                lastRefresh: health.lastScan
            )
        }

        let providerTabs = [ProviderTabItem(id: "overview", name: "总览", status: .ready)] + descriptors.map { descriptor in
            ProviderTabItem(
                id: descriptor.id,
                name: shortProviderName(for: descriptor),
                status: sourceHealth[descriptor.id]?.status ?? .unavailable
            )
        }

        let todayMetrics = try await todaySummary.metrics
        let currentWeekMetrics = try await currentWeekSummary.metrics
        let overallCached = try await overallCachedBreakdown.reduce(0) { $0 + $1.value }
        let overview = OverviewPanelSnapshot(
            todayTokens: todayMetrics.todayTokens,
            sevenDayTokens: currentWeekMetrics.todayTokens,
            cachedTokens: overallCached,
            activeSources: todayMetrics.activeSources,
            trendPoints: normalizeWeekTrend(try await overallTrend, week: currentWeek, calendar: calendar),
            providerRows: descriptors.map { descriptor in
                let panel = panelsByID[descriptor.id]
                return OverviewProviderRow(
                    id: descriptor.id,
                    name: shortProviderName(for: descriptor),
                    todayTokens: panel?.todayTokens ?? 0,
                    status: sourceHealth[descriptor.id]?.status ?? .unavailable
                )
            },
            lastRefresh: now
        )

        let selectedTabID = resolvedSelectedTabID(
            preferredTabID: preferredTabID,
            providerTabs: providerTabs,
            panelsByID: panelsByID,
            overview: overview
        )

        return AppSnapshot(
            providerTabs: providerTabs,
            selectedTabID: selectedTabID,
            overview: overview,
            panelsByID: panelsByID,
            lastRefresh: now
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

    private func shortProviderName(for descriptor: SourceDescriptor) -> String {
        switch descriptor.id {
        case "codex": return "Codex"
        case "claude-code": return "Claude"
        case "gemini": return "Gemini"
        default: return descriptor.displayName
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
}

private struct WeekWindow {
    let start: Date
    let end: Date
    let days: [Date]
}
