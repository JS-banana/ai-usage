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
        VStack(alignment: .leading, spacing: 8) {
            providerTabs
            if let activeEntitlementSummary = displayedEntitlementSummary {
                entitlementSummaryCard(activeEntitlementSummary)
            }
            summaryCard
            actionToolbar
            statusRow
        }
        .padding(10)
        .frame(minWidth: 380, idealWidth: 400, maxWidth: 430, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerTabs: some View {
        HStack(spacing: 6) {
            ForEach(appState.providerTabs) { tab in
                ProviderTabButton(tab: tab, isSelected: appState.selectedTabID == tab.id) {
                    appState.selectTab(tab.id)
                }
            }
        }
    }

    private func entitlementSummaryCard(_ summary: EntitlementSummarySnapshot) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 8) {
                QuotaSummarySection(summary: summary, compact: true)
                if summary.status == .failed {
                    Button("重新配置额度") {
                        openSettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var displayedEntitlementSummary: EntitlementSummarySnapshot? {
        guard let summary = appState.activeEntitlementSummary, summary.status != .unconfigured else {
            return nil
        }
        return summary
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
        VStack(alignment: .leading, spacing: 8) {
            if let overview = appState.overviewPanel {
                Text("更新于 \(relativeRefreshText(overview.lastRefresh))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                CompactMetricGrid(items: [
                    MetricGridItem(title: "今日 Tokens", value: fullValue(overview.todayTokens)),
                    MetricGridItem(title: "今日请求", value: overview.todayRequests.formatted()),
                    MetricGridItem(title: "本周 Tokens", value: fullValue(overview.sevenDayTokens)),
                    MetricGridItem(title: "本周请求", value: overview.sevenDayRequests.formatted())
                ])

                if overview.trendPoints.isEmpty == false {
                    Divider()
                    TrendContent(title: "近 7 天", points: overview.trendPoints, chartHeight: 66)
                }
            } else {
                SectionEmptyState(title: "暂无总览数据", message: "启用来源并完成刷新后会显示统计。")
            }
        }
    }

    private func providerSummary(_ panel: ProviderPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastRefreshText(for: panel))
                .font(.caption)
                .foregroundStyle(.secondary)

            CompactMetricGrid(items: [
                MetricGridItem(title: "今日 Tokens", value: fullValue(panel.todayTokens)),
                MetricGridItem(title: "今日请求", value: panel.todayRequests.formatted()),
                MetricGridItem(title: "本周 Tokens", value: fullValue(panel.sevenDayTokens)),
                MetricGridItem(title: "本周请求", value: panel.sevenDayRequests.formatted())
            ])

            if panel.trendPoints.isEmpty == false {
                Divider()
                TrendContent(title: "近 7 天", points: panel.trendPoints, chartHeight: 66)
            }

            Text(panel.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionToolbar: some View {
        PanelCard {
            HStack(spacing: 8) {
                CompactActionButton(title: appState.isLoading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise") {
                    Task { await appState.refresh() }
                }
                CompactActionButton(title: "管理账号", systemImage: "person.crop.circle.badge.plus") {
                    openSettings()
                }
                CompactActionButton(title: "Quota Targets", systemImage: "slider.horizontal.3") {
                    openSettings()
                }
                CompactActionButton(title: "Dashboard", systemImage: "rectangle.grid.2x2") {
                    openWindow(id: "detail")
                }
                CompactActionButton(title: "关于 AiUsage", systemImage: "info.circle") {
                    showAbout()
                }
                CompactActionButton(title: "退出", systemImage: "xmark.circle") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var statusRow: some View {
        Text(appState.statusMessage)
            .font(.caption)
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct ProviderTabButton: View {
    let tab: ProviderTabItem
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color {
        tab.branding.accentColor.tintColor
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ProviderTabLogoView(branding: tab.branding, accentColor: accentColor)
                    .frame(width: 18, height: 18)
                    .frame(maxWidth: .infinity, minHeight: 20)
                ProviderTabMiniProgress(
                    progress: tab.usageProgress,
                    accentColor: accentColor,
                    status: tab.status
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.16) : Color.primary.opacity(0.03))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
            }
            .opacity(tab.status.tabOpacity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.name))
    }
}

private struct ProviderTabLogoView: View {
    let branding: ProviderTabBranding
    let accentColor: Color

    var body: some View {
        Group {
            if let resourceImage = ProviderBrandIcon.image(for: branding) {
                Image(nsImage: resourceImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(accentColor)
            } else {
                switch branding.fallbackIcon {
                case .symbol(let systemName):
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                case .monogram(let value):
                    Text(value)
                        .font(.system(size: value.count > 1 ? 10 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}

private struct ProviderTabMiniProgress: View {
    let progress: Double?
    let accentColor: Color
    let status: SourceStatus

    var body: some View {
        GeometryReader { geometry in
            let ratio = progress.map { min(max($0, 0), 1) }
            let fillWidth = fillWidth(for: geometry.size.width, progress: ratio)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(accentColor.opacity(status.progressOpacity))
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 4)
    }

    private func fillWidth(for totalWidth: CGFloat, progress: Double?) -> CGFloat {
        if let progress {
            return totalWidth * progress
        }
        return 0
    }
}

private struct CompactActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(isHovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
        .overlay(alignment: .top) {
            if isHovered {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .offset(y: -30)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
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
}

private struct CompactMetricGrid: View {
    let items: [MetricGridItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
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
        VStack(alignment: .leading, spacing: 8) {
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
            .frame(height: 24)

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("日期", point.label),
                        y: .value("Tokens", point.value)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .opacity(hoveredPoint == nil || hoveredPoint?.id == point.id ? 1 : 0.45)
                    .cornerRadius(4)

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

private extension ProviderBrandColor {
    var tintColor: Color {
        Color(red: self.red, green: self.green, blue: self.blue)
    }
}

private extension SourceStatus {
    var tabOpacity: Double {
        switch self {
        case .ready:
            return 1
        case .warning:
            return 0.82
        case .unavailable:
            return 0.52
        }
    }

    var progressOpacity: Double {
        switch self {
        case .ready:
            return 0.95
        case .warning:
            return 0.72
        case .unavailable:
            return 0.35
        }
    }
}
