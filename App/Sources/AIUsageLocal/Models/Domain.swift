import Foundation

struct SourceHealth: Identifiable, Hashable {
    let id: String
    let name: String
    var discoveredFiles: Int
    var importedSessions: Int
    var lastScan: Date?
    var status: SourceStatus
    var message: String
}

enum SourceStatus: String, CaseIterable, Hashable {
    case ready
    case warning
    case unavailable
}

struct UsageEvent: Identifiable, Hashable {
    let id: String
    let source: String
    let model: String
    let project: String
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let totalTokens: Int
}

struct SessionSummary: Identifiable, Hashable {
    let id: String
    let source: String
    let model: String
    let project: String
    let startedAt: Date
    let endedAt: Date
    let messages: Int
    let totalTokens: Int
    let filePath: String
}

struct ParsedFileResult {
    var events: [UsageEvent]
    var sessions: [SessionSummary]
}

struct DashboardMetrics {
    var todayTokens: Int
    var sevenDayTokens: Int
    var sessionCount: Int
    var activeSources: Int
}

struct BucketPoint: Identifiable, Hashable {
    let id: String
    let label: String
    let value: Int
}

struct BreakdownItem: Identifiable, Hashable {
    let id: String
    let name: String
    let value: Int
}
