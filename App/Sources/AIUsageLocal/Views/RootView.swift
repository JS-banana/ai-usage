import SwiftUI
import Charts
import AppKit
import Domain
import Query
import Support

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerTabs
            panelBody
            actionsRow
        }
        .padding(14)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerTabs: some View {
        HStack(spacing: 8) {
            ForEach(appState.providerTabs) { tab in
                Button {
                    appState.selectTab(tab.id)
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color(for: tab.status))
                                .frame(width: 7, height: 7)
                            Text(tab.name)
                                .font(.subheadline.weight(.semibold))
                        }
                        Capsule()
                            .fill(appState.selectedTabID == tab.id ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(appState.selectedTabID == tab.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        if appState.selectedTabID == "overview" {
            overviewCard
            overviewTrendCard
        } else {
            summaryCard
            miniTrendCard
            statusCard
        }
    }

    private var overviewCard: some View {
        PanelCard {
            if let overview = appState.overviewPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总览")
                                .font(.title3.bold())
                            Text("更新于 \(relativeRefreshText(overview.lastRefresh))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(title: "\(overview.activeSources) 个来源活跃", color: overview.activeSources > 0 ? .green : .gray)
                    }

                    TwoColumnMetricGrid(items: [
                        MetricGridItem(title: "今日总 Tokens", value: fullValue(overview.todayTokens), note: approxNote(overview.todayTokens)),
                        MetricGridItem(title: "本周", value: fullValue(overview.sevenDayTokens), note: approxNote(overview.sevenDayTokens)),
                        MetricGridItem(title: "今日 Cached", value: fullValue(overview.cachedTokens), note: approxNote(overview.cachedTokens)),
                        MetricGridItem(title: "活跃来源", value: overview.activeSources.formatted(), note: nil)
                    ])

                    Divider()

                    VStack(spacing: 8) {
                        ForEach(overview.providerRows) { row in
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(color(for: row.status))
                                        .frame(width: 7, height: 7)
                                    Text(row.name)
                                        .font(.subheadline.weight(.medium))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(fullValue(row.todayTokens))
                                        .font(.subheadline.monospacedDigit())
                                    if let note = approxNote(row.todayTokens) {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                SectionEmptyState(title: "暂无总览数据", message: "有来源数据后，这里会显示总览。")
            }
        }
    }

    private var summaryCard: some View {
        PanelCard {
            if let panel = appState.selectedPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(panel.name)
                                .font(.title3.bold())
                            Text(lastRefreshText(for: panel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(title: statusLabel(for: panel.status), color: color(for: panel.status))
                    }

                    TwoColumnMetricGrid(items: [
                        MetricGridItem(title: "今日", value: fullValue(panel.todayTokens), note: approxNote(panel.todayTokens)),
                        MetricGridItem(title: "本周", value: fullValue(panel.sevenDayTokens), note: approxNote(panel.sevenDayTokens)),
                        MetricGridItem(title: "Cached", value: fullValue(panel.cachedTokens), note: approxNote(panel.cachedTokens)),
                        MetricGridItem(title: "已导入会话", value: panel.importedSessions.formatted(), note: nil)
                    ])
                }
            } else {
                SectionEmptyState(title: "暂无来源数据", message: "有可用来源后，这里会显示摘要信息。")
            }
        }
    }

    private var overviewTrendCard: some View {
        PanelCard {
            if let overview = appState.overviewPanel, overview.trendPoints.isEmpty == false {
                TrendContent(title: "本周", points: overview.trendPoints)
            } else {
                SectionEmptyState(title: "暂无趋势", message: "本周有数据后会显示在这里。")
            }
        }
    }

    private var miniTrendCard: some View {
        PanelCard {
            if let panel = appState.selectedPanel, panel.trendPoints.isEmpty == false {
                TrendContent(title: "本周", points: panel.trendPoints)
            } else {
                SectionEmptyState(title: "暂无趋势", message: "本周有数据后会显示在这里。")
            }
        }
    }

    private var statusCard: some View {
        PanelCard {
            if let panel = appState.selectedPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(panel.message)
                        .font(.subheadline)
                    MiniMetricRow(title: "最近更新", value: panel.lastRefresh?.formatted(date: .omitted, time: .shortened) ?? "—")
                }
            } else {
                SectionEmptyState(title: "暂无状态", message: "来源可用后这里会显示状态。")
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await appState.refresh() }
            } label: {
                Label(appState.isLoading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func statusLabel(for status: SourceStatus) -> String {
        switch status {
        case .ready: "正常"
        case .warning: "提醒"
        case .unavailable: "不可用"
        }
    }

    private func color(for status: SourceStatus) -> Color {
        switch status {
        case .ready: .green
        case .warning: .orange
        case .unavailable: .gray
        }
    }

    private func lastRefreshText(for panel: ProviderPanelSnapshot) -> String {
        guard let lastRefresh = panel.lastRefresh else { return appState.statusMessage }
        return "更新于 \(relativeRefreshText(lastRefresh))"
    }

    private func fullValue(_ value: Int) -> String {
        CompactNumberFormatting.fullString(value)
    }

    private func approxNote(_ value: Int) -> String? {
        CompactNumberFormatting.approximateInYi(value)
    }

    private func hoverLabel(for point: BucketPoint) -> String {
        "\(point.label) · \(point.id)"
    }

    private func relativeRefreshText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct TrendContent: View {
    let title: String
    let points: [BucketPoint]
    var chartHeight: CGFloat = 92

    @State private var hoveredPoint: BucketPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .trailing) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let hoveredPoint {
                    TrendHoverBadge(
                        label: "\(hoveredPoint.label) · \(hoveredPoint.id)",
                        value: CompactNumberFormatting.fullString(hoveredPoint.value)
                    )
                }
            }
            .frame(height: 28)

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("日期", point.label),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .opacity(hoveredPoint == nil || hoveredPoint?.id == point.id ? 1 : 0.45)
                    .cornerRadius(5)

                    if hoveredPoint?.id == point.id {
                        RuleMark(x: .value("日期", point.label))
                            .foregroundStyle(Color.accentColor.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard let plotFrame = proxy.plotFrame else {
                                hoveredPoint = nil
                                return
                            }

                            let frame = geometry[plotFrame]

                            switch phase {
                            case .active(let location):
                                guard frame.contains(location), points.isEmpty == false else {
                                    hoveredPoint = nil
                                    return
                                }

                                let relativeX = max(0, min(location.x - frame.minX, frame.width))
                                let bucketWidth = frame.width / CGFloat(points.count)
                                let index = min(max(Int(relativeX / max(bucketWidth, 1)), 0), points.count - 1)
                                hoveredPoint = points[index]
                            case .ended:
                                hoveredPoint = nil
                            }
                        }
                }
            }
            .frame(height: chartHeight)
        }
    }
}

private struct TrendHoverBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct MetricGridItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let note: String?
}

private struct TwoColumnMetricGrid: View {
    let items: [MetricGridItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    if let note = item.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.bold())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct MiniMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

private struct SectionEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}
