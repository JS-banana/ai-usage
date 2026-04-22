import Foundation
import Domain
import Persistence

public struct LiveDashboardQueryService: DashboardQueryServing {
    private let analytics: AnalyticsQuerying

    public init(analytics: AnalyticsQuerying) {
        self.analytics = analytics
    }

    public func summary(range: DateRange) async throws -> DashboardSummary {
        DashboardSummary(metrics: try await analytics.dashboardMetrics(start: range.start, end: range.end))
    }

    public func summary(range: DateRange, sourceIDs: [String]) async throws -> DashboardSummary {
        DashboardSummary(metrics: try await analytics.dashboardMetrics(start: range.start, end: range.end, sourceIDs: sourceIDs))
    }

    public func trend(range: DateRange, granularity: TrendGranularity) async throws -> [BucketPoint] {
        try await analytics.trend(start: range.start, end: range.end, granularity: granularity, calendar: .current)
    }

    public func trend(range: DateRange, granularity: TrendGranularity, sourceIDs: [String]) async throws -> [BucketPoint] {
        try await analytics.trend(start: range.start, end: range.end, granularity: granularity, calendar: .current, sourceIDs: sourceIDs)
    }

    public func breakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem] {
        try await analytics.breakdownBySource(start: range.start, end: range.end, limit: limit)
    }

    public func cachedBreakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem] {
        try await analytics.cachedBreakdownBySource(start: range.start, end: range.end, limit: limit)
    }

    public func breakdownByModel(range: DateRange, limit: Int) async throws -> [BreakdownItem] {
        try await analytics.breakdownByModel(start: range.start, end: range.end, limit: limit)
    }

    public func breakdownByProject(range: DateRange, limit: Int) async throws -> [BreakdownItem] {
        try await analytics.breakdownByProject(start: range.start, end: range.end, limit: limit)
    }
}
