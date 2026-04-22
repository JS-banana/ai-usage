import Foundation
import Persistence

public struct LiveSourceHealthQueryService: SourceHealthQueryServing {
    private let analytics: AnalyticsQuerying

    public init(analytics: AnalyticsQuerying) {
        self.analytics = analytics
    }

    public func sourceOverview() async throws -> [SourceHealthItem] {
        try await analytics.sourceHealthOverview().map { SourceHealthItem(id: $0.id, health: $0) }
    }

    public func latestDiagnostics(sourceID: String, limit: Int) async throws -> [DiagnosticListItem] {
        try await analytics.latestDiagnostics(sourceID: sourceID, limit: limit).map { DiagnosticListItem(id: $0.id, diagnostic: $0) }
    }
}
