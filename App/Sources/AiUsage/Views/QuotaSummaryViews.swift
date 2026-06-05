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
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(summary.primaryWindow.primaryText.isEmpty ? "额度刷新失败" : summary.primaryWindow.primaryText)
                        .font(.caption.weight(.semibold))
                    if summary.message.isEmpty == false {
                        Text(summary.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                let windows = summary.visibleWindows
                if windows.isEmpty == false {
                    VStack(spacing: 8) {
                        ForEach(Array(windows.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 8) {
                                ForEach(row) { window in
                                    CompactQuotaWindowCard(window: window, compact: compact)
                                }
                            }
                        }
                    }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if window.detailText.isEmpty == false {
                    Text(window.detailText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if window.progress != nil {
                QuotaProgressTrack(progress: window.progress, compact: compact)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.primaryText)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if window.secondaryText.isEmpty == false {
                    Text(window.secondaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if window.footnoteText.isEmpty == false {
                Text(window.footnoteText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
