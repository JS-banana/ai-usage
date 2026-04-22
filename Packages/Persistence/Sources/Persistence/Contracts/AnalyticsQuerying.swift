import Foundation
import Domain

public protocol AnalyticsQuerying: Sendable {
    func dashboardMetrics(start: Date?, end: Date?) async throws -> DashboardMetrics
    func dashboardMetrics(start: Date?, end: Date?, sourceIDs: [String]) async throws -> DashboardMetrics
    func trend(start: Date?, end: Date?, granularity: TrendGranularity, calendar: Calendar) async throws -> [BucketPoint]
    func trend(start: Date?, end: Date?, granularity: TrendGranularity, calendar: Calendar, sourceIDs: [String]) async throws -> [BucketPoint]
    func breakdownBySource(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem]
    func cachedBreakdownBySource(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem]
    func breakdownByModel(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem]
    func breakdownByProject(start: Date?, end: Date?, limit: Int) async throws -> [BreakdownItem]
    func recentSessions(limit: Int) async throws -> [SessionSummary]
    func sessions(filter: QueryFilters, limit: Int?) async throws -> [SessionSummary]
    func sourceHealthOverview() async throws -> [SourceHealth]
    func latestDiagnostics(sourceID: String, limit: Int) async throws -> [ParserDiagnostic]
}
