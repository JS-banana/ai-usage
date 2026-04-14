import Foundation
import Observation
import Domain

@Observable
final class AppState {
    var isLoading = false
    var lastRefresh: Date?
    var statusMessage = "准备就绪"
    var metrics = DashboardMetrics(todayTokens: 0, sevenDayTokens: 0, sessionCount: 0, activeSources: 0)
    var trendPoints: [BucketPoint] = []
    var sourceBreakdown: [BreakdownItem] = []
    var modelBreakdown: [BreakdownItem] = []
    var projectBreakdown: [BreakdownItem] = []
    var recentSessions: [SessionSummary] = []
    var sourceHealth: [SourceHealth] = []

    private let ingestionService = IngestionService()

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        statusMessage = "正在扫描本地数据源…"
        defer { isLoading = false }

        do {
            let snapshot = try await ingestionService.refreshAll()
            metrics = snapshot.metrics
            trendPoints = snapshot.trendPoints
            sourceBreakdown = snapshot.sourceBreakdown
            modelBreakdown = snapshot.modelBreakdown
            projectBreakdown = snapshot.projectBreakdown
            recentSessions = snapshot.recentSessions
            sourceHealth = snapshot.sourceHealth
            lastRefresh = Date()
            statusMessage = "已完成扫描，共导入 \(snapshot.metrics.sessionCount) 个会话"
        } catch {
            statusMessage = "扫描失败：\(error.localizedDescription)"
        }
    }
}
