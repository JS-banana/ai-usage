import Foundation
import Domain

public protocol DashboardQueryServing: Sendable {
    func summary(range: DateRange) async throws -> DashboardSummary
    func trend(range: DateRange, granularity: TrendGranularity) async throws -> [BucketPoint]
    func breakdownBySource(range: DateRange, limit: Int) async throws -> [BreakdownRow]
    func breakdownByModel(range: DateRange, limit: Int) async throws -> [BreakdownRow]
    func breakdownByProject(range: DateRange, limit: Int) async throws -> [BreakdownRow]
}

public protocol SessionsQueryServing: Sendable {
    func recentSessions(limit: Int) async throws -> [SessionListItem]
    func sessions(filter: SessionFilter) async throws -> [SessionListItem]
}

public protocol SourceHealthQueryServing: Sendable {
    func sourceOverview() async throws -> [SourceHealthItem]
    func latestDiagnostics(sourceID: String, limit: Int) async throws -> [DiagnosticListItem]
}
