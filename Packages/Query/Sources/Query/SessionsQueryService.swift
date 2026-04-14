import Foundation

public struct PlaceholderSessionsQueryService: SessionsQueryServing {
    public init() {}

    public func recentSessions(limit: Int) async throws -> [SessionListItem] {
        []
    }

    public func sessions(filter: SessionFilter) async throws -> [SessionListItem] {
        []
    }
}
