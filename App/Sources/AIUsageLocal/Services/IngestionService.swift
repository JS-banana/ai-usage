import Foundation

struct IngestionSnapshot {
    let metrics: DashboardMetrics
    let trendPoints: [BucketPoint]
    let sourceBreakdown: [BreakdownItem]
    let modelBreakdown: [BreakdownItem]
    let projectBreakdown: [BreakdownItem]
    let recentSessions: [SessionSummary]
    let sourceHealth: [SourceHealth]
}

actor IngestionService {
    private let parsers: [UsageParser] = [
        ClaudeCodeParser(),
        CodexParser(),
        OpenCodeParser(),
        GeminiParser()
    ]

    func refreshAll() async throws -> IngestionSnapshot {
        var allEvents: [UsageEvent] = []
        var allSessions: [SessionSummary] = []
        var health: [SourceHealth] = []

        for parser in parsers {
            let files = parser.discoverCandidates()
            let parsed = parser.parse(files: files)
            allEvents.append(contentsOf: parsed.events)
            allSessions.append(contentsOf: parsed.sessions)
            health.append(SourceHealth(
                id: parser.sourceID,
                name: parser.displayName,
                discoveredFiles: files.count,
                importedSessions: parsed.sessions.count,
                lastScan: Date(),
                status: files.isEmpty ? .warning : .ready,
                message: files.isEmpty ? "未发现数据文件" : "已导入 \(parsed.sessions.count) 个会话"
            ))
        }

        return IngestionSnapshot(
            metrics: buildMetrics(events: allEvents, sessions: allSessions),
            trendPoints: buildTrend(events: allEvents),
            sourceBreakdown: topBreakdown(items: Dictionary(grouping: allEvents, by: { $0.source }).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }),
            modelBreakdown: topBreakdown(items: Dictionary(grouping: allEvents, by: { $0.model }).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }),
            projectBreakdown: topBreakdown(items: Dictionary(grouping: allEvents, by: { $0.project }).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }),
            recentSessions: Array(allSessions.sorted(by: { $0.endedAt > $1.endedAt }).prefix(20)),
            sourceHealth: health
        )
    }

    private func buildMetrics(events: [UsageEvent], sessions: [SessionSummary]) -> DashboardMetrics {
        let now = Date()
        let calendar = Calendar.current
        let todayTokens = events.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }.reduce(0) { $0 + $1.totalTokens }
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let sevenDayTokens = events.filter { $0.timestamp >= sevenDaysAgo }.reduce(0) { $0 + $1.totalTokens }
        let activeSources = Set(events.map { $0.source }).count
        return DashboardMetrics(todayTokens: todayTokens, sevenDayTokens: sevenDayTokens, sessionCount: sessions.count, activeSources: activeSources)
    }

    private func buildTrend(events: [UsageEvent]) -> [BucketPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted().map { day in
            BucketPoint(id: formatter.string(from: day), label: formatter.string(from: day), value: grouped[day, default: []].reduce(0) { $0 + $1.totalTokens })
        }
    }

    private func topBreakdown(items: [String: Int]) -> [BreakdownItem] {
        items.sorted { $0.value > $1.value }.prefix(8).map {
            BreakdownItem(id: $0.key, name: $0.key, value: $0.value)
        }
    }
}
