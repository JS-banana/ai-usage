import Foundation
import Domain

public struct DateRange: Hashable, Sendable {
    public let start: Date?
    public let end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public struct DashboardSummary: Sendable {
    public let metrics: DashboardMetrics

    public init(metrics: DashboardMetrics) {
        self.metrics = metrics
    }
}

public struct SessionFilter: Sendable {
    public let sourceIDs: [String]
    public let models: [String]
    public let projects: [String]
    public let range: DateRange

    public init(sourceIDs: [String] = [], models: [String] = [], projects: [String] = [], range: DateRange = .init()) {
        self.sourceIDs = sourceIDs
        self.models = models
        self.projects = projects
        self.range = range
    }
}

public struct SessionListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let summary: SessionSummary

    public init(id: String, summary: SessionSummary) {
        self.id = id
        self.summary = summary
    }
}

public struct ProviderPanelSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let todayTokens: Int
    public let sevenDayTokens: Int
    public let todayRequests: Int
    public let sevenDayRequests: Int
    public let cachedTokens: Int
    public let status: SourceStatus
    public let message: String
    public let trendPoints: [BucketPoint]
    public let importedSessions: Int
    public let lastRefresh: Date?

    public init(
        id: String,
        name: String,
        todayTokens: Int,
        sevenDayTokens: Int,
        todayRequests: Int,
        sevenDayRequests: Int,
        cachedTokens: Int,
        status: SourceStatus,
        message: String,
        trendPoints: [BucketPoint],
        importedSessions: Int,
        lastRefresh: Date?
    ) {
        self.id = id
        self.name = name
        self.todayTokens = todayTokens
        self.sevenDayTokens = sevenDayTokens
        self.todayRequests = todayRequests
        self.sevenDayRequests = sevenDayRequests
        self.cachedTokens = cachedTokens
        self.status = status
        self.message = message
        self.trendPoints = trendPoints
        self.importedSessions = importedSessions
        self.lastRefresh = lastRefresh
    }
}

public struct SourceHealthItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let health: SourceHealth

    public init(id: String, health: SourceHealth) {
        self.id = id
        self.health = health
    }
}

public struct DiagnosticListItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let diagnostic: ParserDiagnostic

    public init(id: String, diagnostic: ParserDiagnostic) {
        self.id = id
        self.diagnostic = diagnostic
    }
}
