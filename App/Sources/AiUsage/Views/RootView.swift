import SwiftUI
import Charts
import AppKit
import Domain
import Query
import Support

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerTabs
            if shouldShowQuotaSummary {
                quotaSummaryCard
            }
            summaryCard
            actionList
            statusRow
        }
        .padding(12)
        .frame(minWidth: 380, idealWidth: 400, maxWidth: 430, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerTabs: some View {
        HStack(spacing: 6) {
            ForEach(appState.providerTabs) { tab in
                Button {
                    appState.selectTab(tab.id)
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color(for: tab.status))
                                .frame(width: 6, height: 6)
                            Text(tab.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        Capsule()
                            .fill(appState.selectedTabID == tab.id ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(appState.selectedTabID == tab.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quotaSummaryCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 8) {
                QuotaSummarySection(summary: appState.groupQuotaSummary, compact: true)
                if appState.groupQuotaSummary.status == .failed {
                    Button("重新配置额度") {
                        openSettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var shouldShowQuotaSummary: Bool {
        appState.groupQuotaSummary.status != .unconfigured
    }

    private var summaryCard: some View {
        PanelCard {
            if appState.selectedTabID == "overview" {
                overviewSummary
            } else if let panel = appState.selectedPanel {
                providerSummary(panel)
            } else {
                SectionEmptyState(title: "暂无来源数据", message: "在下方添加或启用账号来源后，这里会显示统计。")
            }
        }
    }

    private var overviewSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("总览")
                        .font(.title3.bold())
                    if let overview = appState.overviewPanel {
                        Text("更新于 \(relativeRefreshText(overview.lastRefresh))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let overview = appState.overviewPanel {
                    StatusPill(title: "\(overview.activeSources) 个来源", color: overview.activeSources > 0 ? .green : .gray)
                }
            }

            if let overview = appState.overviewPanel {
                CompactMetricGrid(items: [
                    MetricGridItem(title: "今日 Tokens", value: fullValue(overview.todayTokens), note: nil),
                    MetricGridItem(title: "今日请求", value: overview.todayRequests.formatted(), note: nil),
                    MetricGridItem(title: "本周 Tokens", value: fullValue(overview.sevenDayTokens), note: nil),
                    MetricGridItem(title: "今日 Cached", value: fullValue(overview.cachedTokens), note: nil)
                ])

                if overview.trendPoints.isEmpty == false {
                    Divider()
                    TrendContent(title: "近 7 天", points: overview.trendPoints, chartHeight: 70)
                }

                if overview.providerRows.isEmpty == false {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(overview.providerRows.prefix(4)) { row in
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(color(for: row.status))
                                        .frame(width: 6, height: 6)
                                    Text(row.name)
                                        .font(.subheadline.weight(.medium))
                                }
                                Spacer()
                                Text("\(row.todayRequests) 次 · \(fullValue(row.todayTokens))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                SectionEmptyState(title: "暂无总览数据", message: "启用来源并完成刷新后会显示统计。")
            }
        }
    }

    private func providerSummary(_ panel: ProviderPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(panel.name)
                        .font(.title3.bold())
                    Text(lastRefreshText(for: panel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(title: statusLabel(for: panel.status), color: color(for: panel.status))
            }

            CompactMetricGrid(items: [
                MetricGridItem(title: "今日 Tokens", value: fullValue(panel.todayTokens), note: nil),
                MetricGridItem(title: "今日请求", value: panel.todayRequests.formatted(), note: nil),
                MetricGridItem(title: "本周 Tokens", value: fullValue(panel.sevenDayTokens), note: nil),
                MetricGridItem(title: "已导入会话", value: panel.importedSessions.formatted(), note: nil)
            ])

            if panel.trendPoints.isEmpty == false {
                Divider()
                TrendContent(title: "近 7 天", points: panel.trendPoints, chartHeight: 70)
            }

            Text(panel.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionList: some View {
        PanelCard {
            VStack(spacing: 0) {
                ActionRow(title: appState.isLoading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise") {
                    Task { await appState.refresh() }
                }
                Divider().padding(.leading, 30)
                ActionRow(title: "添加 / 管理账号", systemImage: "person.crop.circle.badge.plus") {
                    openSettings()
                }
                Divider().padding(.leading, 30)
                ActionRow(title: "Usage Dashboard", systemImage: "rectangle.grid.2x2") {
                    openWindow(id: "detail")
                }
                Divider().padding(.leading, 30)
                ActionRow(title: "关于 AiUsage", systemImage: "info.circle") {
                    showAbout()
                }
                Divider().padding(.leading, 30)
                ActionRow(title: "退出", systemImage: "xmark.circle") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private var statusRow: some View {
        Text(appState.statusMessage)
            .font(.caption)
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var statusColor: Color {
        if appState.statusMessage.hasPrefix("启动失败") || appState.statusMessage.hasPrefix("刷新失败") {
            return .red
        }
        if appState.statusMessage.localizedCaseInsensitiveContains("Quota 刷新失败") {
            return .orange
        }
        return .secondary
    }

    private func lastRefreshText(for panel: ProviderPanelSnapshot) -> String {
        guard let lastRefresh = panel.lastRefresh else { return appState.statusMessage }
        return "更新于 \(relativeRefreshText(lastRefresh))"
    }

    private func fullValue(_ value: Int) -> String {
        CompactNumberFormatting.fullString(value)
    }

    private func relativeRefreshText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct ActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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

private struct CompactMetricGrid: View {
    let items: [MetricGridItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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

struct MiniMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }
}
