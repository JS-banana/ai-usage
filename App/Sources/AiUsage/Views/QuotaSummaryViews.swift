import SwiftUI

struct QuotaSummarySection: View {
    let summary: GroupQuotaSummarySnapshot
    var title: String = "分组额度"
    var showsHeader: Bool = true
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if showsHeader {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(summary.groupName)
                            .font(compact ? .subheadline.weight(.semibold) : .headline)
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusBadge(title: statusTitle)
                }
            }

            if summary.status == .failed {
                Text("Quota 暂不可用，稍后重试")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    CompactQuotaWindowCard(window: summary.fiveHour, compact: compact)
                    CompactQuotaWindowCard(window: summary.weekly, compact: compact)
                }
            }
        }
    }

    private var statusTitle: String {
        switch summary.status {
        case .ready: return "已配置"
        case .stale: return "偏旧"
        case .failed: return "失败"
        case .unconfigured: return "未配置"
        }
    }
}

private struct CompactQuotaWindowCard: View {
    let window: GroupQuotaWindowSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(window.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if compact == false {
                Text(window.footnoteText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            QuotaProgressTrack(progress: window.progress, compact: compact)

            Text(window.primaryText)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuotaProgressTrack: View {
    let progress: Double?
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let ratio = min(max(progress ?? 0.18, 0.18), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.04)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: compact ? 5 : 6)
    }
}

private struct StatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
