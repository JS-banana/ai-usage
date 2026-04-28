import SwiftUI

enum QuotaProgressRiskLevel: String, Sendable {
    case green
    case yellow
    case orange
    case red

    static func forProgress(_ progress: Double?) -> QuotaProgressRiskLevel {
        let ratio = min(max(progress ?? 0, 0), 1)
        switch ratio {
        case ..<0.35:
            return .green
        case ..<0.60:
            return .yellow
        case ..<0.80:
            return .orange
        default:
            return .red
        }
    }
}

struct QuotaSummarySection: View {
    let summary: EntitlementSummarySnapshot
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if summary.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("套餐额度暂不可用")
                        .font(.subheadline.weight(.semibold))
                    Text(summary.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 8) {
                    CompactQuotaWindowCard(window: summary.primaryWindow, compact: compact)
                    CompactQuotaWindowCard(window: summary.secondaryWindow, compact: compact)
                }
            }
        }
    }
}

private struct CompactQuotaWindowCard: View {
    let window: EntitlementWindowSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(window.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            QuotaProgressTrack(progress: window.progress, compact: compact)

            Text(window.primaryText)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(window.footnoteText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(Color.primary.opacity(compact ? 0.04 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuotaProgressTrack: View {
    let progress: Double?
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let ratio = min(max(progress ?? 0, 0), 1)
            let riskLevel = QuotaProgressRiskLevel.forProgress(progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(riskLevel.color)
                    .frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: compact ? 5 : 6)
    }
}

private extension QuotaProgressRiskLevel {
    var color: Color {
        switch self {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .orange:
            return .orange
        case .red:
            return .red
        }
    }
}
