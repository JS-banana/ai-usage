import SwiftUI
import Charts

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            List {
                Section("概览") {
                    Label("仪表盘", systemImage: "square.grid.2x2")
                    Label("数据源健康", systemImage: "waveform.path.ecg")
                    Label("设置", systemImage: "gearshape")
                }
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    metricsGrid
                    trendSection
                    breakdownSection
                    sessionsSection
                    sourceHealthSection
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Usage Local")
                    .font(.largeTitle.bold())
                Text("纯本地 AI coding usage intelligence for macOS")
                    .foregroundStyle(.secondary)
                Text(appState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                if let lastRefresh = appState.lastRefresh {
                    Text("上次刷新：\(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label(appState.isLoading ? "扫描中…" : "立即刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoading)
            }
        }
    }

    private var metricsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                MetricCard(title: "今日 Tokens", value: appState.metrics.todayTokens.formatted())
                MetricCard(title: "近 7 天 Tokens", value: appState.metrics.sevenDayTokens.formatted())
                MetricCard(title: "会话数", value: appState.metrics.sessionCount.formatted())
                MetricCard(title: "活跃工具", value: appState.metrics.activeSources.formatted())
            }
        }
    }

    private var trendSection: some View {
        SectionCard(title: "趋势") {
            Chart(appState.trendPoints) { point in
                BarMark(x: .value("日期", point.label), y: .value("Tokens", point.value))
                    .foregroundStyle(.blue.gradient)
            }
            .frame(height: 240)
        }
    }

    private var breakdownSection: some View {
        HStack(alignment: .top, spacing: 16) {
            breakdownCard(title: "按工具", items: appState.sourceBreakdown, color: .purple)
            breakdownCard(title: "按模型", items: appState.modelBreakdown, color: .green)
            breakdownCard(title: "按项目", items: appState.projectBreakdown, color: .orange)
        }
    }

    private func breakdownCard(title: String, items: [BreakdownItem], color: Color) -> some View {
        SectionCard(title: title) {
            Chart(items) { item in
                SectorMark(angle: .value("Tokens", item.value), innerRadius: .ratio(0.55))
                    .foregroundStyle(by: .value("Name", item.name))
            }
            .frame(height: 220)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    HStack {
                        Circle().fill(color.opacity(0.7)).frame(width: 8, height: 8)
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text(item.value.formatted())
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionsSection: some View {
        SectionCard(title: "最近会话") {
            LazyVStack(spacing: 10) {
                ForEach(appState.recentSessions) { session in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.project).font(.headline)
                            Text("\(session.source) · \(session.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(session.filePath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(session.totalTokens.formatted())
                                .font(.headline.monospacedDigit())
                            Text("\(session.messages) msgs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var sourceHealthSection: some View {
        SectionCard(title: "数据源健康") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(appState.sourceHealth) { source in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle().fill(color(for: source.status)).frame(width: 10, height: 10)
                            Text(source.name).font(.headline)
                            Spacer()
                            Text(source.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(source.message)
                            .font(.subheadline)
                        HStack {
                            Label("文件 \(source.discoveredFiles)", systemImage: "doc.text")
                            Spacer()
                            Label("会话 \(source.importedSessions)", systemImage: "bubble.left.and.bubble.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func color(for status: SourceStatus) -> Color {
        switch status {
        case .ready: .green
        case .warning: .orange
        case .unavailable: .red
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
            content
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
