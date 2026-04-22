import Foundation
import Domain

public protocol DashboardQueryServing: Sendable {
    func summary(range: DateRange) async throws -> DashboardSummary
    func summary(range: DateRange, sourceIDs: [String]) async throws -> DashboardSummary
    func trend(range: DateRange, granularity: TrendGranularity) async throws -> [BucketPoint]
    func trend(range: DateRange, granularity: TrendGranularity, sourceIDs: [String]) async throws -> [BucketPoint]
    func breakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem]
    func cachedBreakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownItem]
    func breakdownByModel(range: DateRange, limit: Int) async throws -> [BreakdownItem]
    func breakdownByProject(range: DateRange, limit: Int) async throws -> [BreakdownItem]
}

public protocol SessionsQueryServing: Sendable {
    func recentSessions(limit: Int) async throws -> [SessionListItem]
    func sessions(filter: SessionFilter) async throws -> [SessionListItem]
}

public protocol SourceHealthQueryServing: Sendable {
    func sourceOverview() async throws -> [SourceHealthItem]
    func latestDiagnostics(sourceID: String, limit: Int) async throws -> [DiagnosticListItem]
}
