import Foundation
import Persistence

public struct LiveSessionsQueryService: SessionsQueryServing {
    private let analytics: AnalyticsQuerying

    public init(analytics: AnalyticsQuerying) {
        self.analytics = analytics
    }

    public func recentSessions(limit: Int) async throws -> [SessionListItem] {
        try await analytics.recentSessions(limit: limit).map { SessionListItem(id: $0.id, summary: $0) }
    }

    public func sessions(filter: SessionFilter) async throws -> [SessionListItem] {
        let persistenceFilter = QueryFilters(
            sourceIDs: filter.sourceIDs,
            models: filter.models,
            projects: filter.projects,
            startDate: filter.range.start,
            endDate: filter.range.end
        )
        return try await analytics.sessions(filter: persistenceFilter, limit: nil).map { SessionListItem(id: $0.id, summary: $0) }
    }
}
