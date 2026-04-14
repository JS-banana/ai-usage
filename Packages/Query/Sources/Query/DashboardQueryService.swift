import Foundation
import Domain

public struct PlaceholderDashboardQueryService: DashboardQueryServing {
    public init() {}

    public func summary(range: DateRange) async throws -> DashboardSummary {
        DashboardSummary(metrics: DashboardMetrics(todayTokens: 0, sevenDayTokens: 0, sessionCount: 0, activeSources: 0))
    }

    public func trend(range: DateRange, granularity: TrendGranularity) async throws -> [BucketPoint] {
        []
    }

    public func breakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownRow] {
        []
    }

    public func breakdownByModel(range: DateRange, limit: Int) async throws -> [BreakdownRow] {
        []
    }

    public func breakdownByProject(range: DateRange, limit: Int) async throws -> [BreakdownRow] {
        []
    }
}
