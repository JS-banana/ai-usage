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

public enum TrendGranularity: String, Hashable, Sendable {
    case daily
    case hourly
}

public struct DashboardSummary: Sendable {
    public let metrics: DashboardMetrics

    public init(metrics: DashboardMetrics) {
        self.metrics = metrics
    }
}

public struct BreakdownRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let value: Int

    public init(id: String, name: String, value: Int) {
        self.id = id
        self.name = name
        self.value = value
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
