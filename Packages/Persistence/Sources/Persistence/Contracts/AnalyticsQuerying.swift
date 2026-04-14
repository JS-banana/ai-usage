import Foundation
import Domain

public protocol AnalyticsQuerying: Sendable {
    func dashboardMetrics() async throws -> DashboardMetrics
    func recentSessions(limit: Int) async throws -> [SessionSummary]
    func sourceHealthOverview() async throws -> [SourceHealth]
}
