import Foundation

public enum RequestSemantic: String, Hashable, Sendable {
    case assistantResponse
}

public enum MetricConfidence: String, Hashable, Sendable {
    case estimated
    case high
}

public struct SourceHealth: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var discoveredFiles: Int
    public var importedSessions: Int
    public var lastScan: Date?
    public var status: SourceStatus
    public var message: String

    public init(id: String, name: String, discoveredFiles: Int, importedSessions: Int, lastScan: Date?, status: SourceStatus, message: String) {
        self.id = id
        self.name = name
        self.discoveredFiles = discoveredFiles
        self.importedSessions = importedSessions
        self.lastScan = lastScan
        self.status = status
        self.message = message
    }
}

public enum SourceStatus: String, CaseIterable, Hashable, Sendable {
    case ready
    case warning
    case unavailable
}

public struct UsageEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: String
    public let model: String
    public let project: String
    public let timestamp: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let totalTokens: Int
    public let requestCount: Int
    public let requestSemantic: RequestSemantic
    public let requestConfidence: MetricConfidence

    public init(
        id: String,
        source: String,
        model: String,
        project: String,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        totalTokens: Int,
        requestCount: Int = 1,
        requestSemantic: RequestSemantic = .assistantResponse,
        requestConfidence: MetricConfidence = .estimated
    ) {
        self.id = id
        self.source = source
        self.model = model
        self.project = project
        self.timestamp = timestamp
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedTokens = max(0, cachedTokens)
        self.totalTokens = max(0, totalTokens)
        self.requestCount = max(0, requestCount)
        self.requestSemantic = requestSemantic
        self.requestConfidence = requestConfidence
    }
}

public struct SessionSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: String
    public let model: String
    public let project: String
    public let startedAt: Date
    public let endedAt: Date
    public let messages: Int
    public let totalTokens: Int
    public let requestCount: Int
    public let filePath: String

    public init(id: String, source: String, model: String, project: String, startedAt: Date, endedAt: Date, messages: Int, totalTokens: Int, requestCount: Int = 0, filePath: String) {
        self.id = id
        self.source = source
        self.model = model
        self.project = project
        self.startedAt = min(startedAt, endedAt)
        self.endedAt = max(startedAt, endedAt)
        self.messages = max(0, messages)
        self.totalTokens = max(0, totalTokens)
        self.requestCount = max(0, requestCount)
        self.filePath = filePath
    }
}

public struct ParserDiagnostic: Identifiable, Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable {
        case warning
        case error
    }

    public let id: String
    public let severity: Severity
    public let source: String
    public let filePath: String
    public let message: String

    public init(id: String, severity: Severity, source: String, filePath: String, message: String) {
        self.id = id
        self.severity = severity
        self.source = source
        self.filePath = filePath
        self.message = message
    }
}

public struct ParsedFileResult: Sendable {
    public var events: [UsageEvent]
    public var sessions: [SessionSummary]
    public var diagnostics: [ParserDiagnostic]
    public var skippedRecords: Int

    public init(events: [UsageEvent], sessions: [SessionSummary], diagnostics: [ParserDiagnostic] = [], skippedRecords: Int = 0) {
        self.events = events
        self.sessions = sessions
        self.diagnostics = diagnostics
        self.skippedRecords = skippedRecords
    }
}

public struct DashboardMetrics: Sendable {
    public var todayTokens: Int
    public var sevenDayTokens: Int
    public var todayRequests: Int
    public var sevenDayRequests: Int
    public var sessionCount: Int
    public var activeSources: Int

    public init(todayTokens: Int, sevenDayTokens: Int, todayRequests: Int = 0, sevenDayRequests: Int = 0, sessionCount: Int, activeSources: Int) {
        self.todayTokens = todayTokens
        self.sevenDayTokens = sevenDayTokens
        self.todayRequests = todayRequests
        self.sevenDayRequests = sevenDayRequests
        self.sessionCount = sessionCount
        self.activeSources = activeSources
    }
}

public enum TrendGranularity: String, Hashable, Sendable {
    case daily
    case hourly
}

public struct BucketPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: Int

    public init(id: String, label: String, value: Int) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct BreakdownItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let value: Int

    public init(id: String, name: String, value: Int) {
        self.id = id
        self.name = name
        self.value = value
    }
}
