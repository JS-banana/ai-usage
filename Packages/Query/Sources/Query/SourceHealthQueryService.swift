import Foundation

public struct PlaceholderSourceHealthQueryService: SourceHealthQueryServing {
    public init() {}

    public func sourceOverview() async throws -> [SourceHealthItem] {
        []
    }

    public func latestDiagnostics(sourceID: String, limit: Int) async throws -> [DiagnosticListItem] {
        []
    }
}
