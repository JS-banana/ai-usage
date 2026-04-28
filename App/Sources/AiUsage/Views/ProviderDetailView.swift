import SwiftUI
import Charts
import Query
import Support

struct ProviderDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let entitlementSummary = displayedEntitlementSummary {
                    PanelDetailCard(title: "套餐额度") {
                        QuotaSummarySection(summary: entitlementSummary)
                    }
                }

                if appState.selectedTabID == "overview", let overview = appState.overviewPanel {
                    HStack(spacing: 16) {
                        DetailMetricCard(title: "今日", value: CompactNumberFormatting.fullString(overview.todayTokens))
                        DetailMetricCard(title: "本周", value: CompactNumberFormatting.fullString(overview.sevenDayTokens))
                        DetailMetricCard(title: "今日请求", value: overview.todayRequests.formatted())
                        DetailMetricCard(title: "本周请求", value: overview.sevenDayRequests.formatted())
                        DetailMetricCard(title: "Cached", value: CompactNumberFormatting.fullString(overview.cachedTokens))
                    }

                    PanelDetailCard(title: "趋势") {
                        if overview.trendPoints.isEmpty {
                            Text("本周暂无数据")
                                .foregroundStyle(.secondary)
                        } else {
                            TrendContent(title: "本周", points: overview.trendPoints, chartHeight: 240)
                        }
                    }
                } else if let panel = appState.selectedPanel {
                    HStack(spacing: 16) {
                        DetailMetricCard(title: "今日", value: CompactNumberFormatting.fullString(panel.todayTokens))
                        DetailMetricCard(title: "本周", value: CompactNumberFormatting.fullString(panel.sevenDayTokens))
                        DetailMetricCard(title: "今日请求", value: panel.todayRequests.formatted())
                        DetailMetricCard(title: "本周请求", value: panel.sevenDayRequests.formatted())
                        DetailMetricCard(title: "Cached", value: CompactNumberFormatting.fullString(panel.cachedTokens))
                    }

                    PanelDetailCard(title: "趋势") {
                        if panel.trendPoints.isEmpty {
                            Text("本周暂无数据")
                                .foregroundStyle(.secondary)
                        } else {
                            TrendContent(title: "本周", points: panel.trendPoints, chartHeight: 240)
                        }
                    }

                    PanelDetailCard(title: "状态") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(panel.message)
                            MiniMetricRow(title: "请求次数", value: panel.todayRequests.formatted())
                            MiniMetricRow(title: "已导入会话", value: panel.importedSessions.formatted())
                            if let lastRefresh = panel.lastRefresh {
                                MiniMetricRow(title: "最近更新", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                } else {
                    Text("暂无详情数据")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var displayedEntitlementSummary: EntitlementSummarySnapshot? {
        guard let summary = appState.activeEntitlementSummary, summary.status != .unconfigured else {
            return nil
        }
        return summary
    }
}

private struct DetailMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PanelDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
