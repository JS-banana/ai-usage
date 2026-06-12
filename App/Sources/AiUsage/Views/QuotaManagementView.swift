import SwiftUI

struct QuotaManagementView: View {
    let groups: [QuotaVendorGroupSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if groups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无额度账号")
                        .font(.subheadline.weight(.semibold))
                    Text("添加账号后会显示套餐余量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                ForEach(groups) { group in
                    quotaVendorGroup(group)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func quotaVendorGroup(_ group: QuotaVendorGroupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let summary = group.summary {
                QuotaSummarySection(summary: summary, compact: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.accounts) { account in
                    quotaAccountCard(account)
                }
            }
        }
    }

    private func quotaAccountCard(_ account: QuotaAccountRowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title)
                        .font(.caption.weight(.medium))
                    if account.subtitle.isEmpty == false {
                        Text(account.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if account.planName.isEmpty == false {
                    Text(account.planName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            if let summary = account.summary, summary.status != .unconfigured {
                if summary.status == .failed {
                    quotaFailedAccountBody(summary: summary, footerStatusText: account.footerStatusText)
                } else {
                    quotaReadyAccountBody(summary: summary, footerStatusText: account.footerStatusText)
                }
            } else {
                quotaFallbackAccountBody(account)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(accountCardBackgroundColor(for: account), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func quotaReadyAccountBody(summary: EntitlementSummarySnapshot, footerStatusText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.primaryWindow.detailText.isEmpty == false || summary.primaryWindow.secondaryText.isEmpty == false {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.primaryWindow.detailText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)

                    Text(summary.primaryWindow.secondaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if summary.primaryWindow.progress != nil {
                accountProgressTrack(progress: summary.primaryWindow.progress)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.primaryWindow.primaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(footerStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func quotaFailedAccountBody(summary: EntitlementSummarySnapshot, footerStatusText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(summary.primaryWindow.primaryText.isEmpty ? "额度刷新失败" : summary.primaryWindow.primaryText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }

            if summary.primaryWindow.secondaryText.isEmpty == false {
                Text(summary.primaryWindow.secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if summary.primaryWindow.detailText.isEmpty == false {
                    Text(summary.primaryWindow.detailText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Text(footerStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func quotaFallbackAccountBody(_ account: QuotaAccountRowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(accountFallbackMessage(for: account))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(accountFallbackPrimaryText(for: account))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(account.footerStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func accountProgressTrack(progress: Double?) -> some View {
        GeometryReader { geometry in
            let ratio = min(max(progress ?? 0, 0), 1)
            let riskLevel = QuotaProgressRiskLevel.forProgress(progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(accountProgressColor(for: riskLevel))
                    .frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: 5)
    }

    private func accountFallbackMessage(for account: QuotaAccountRowSnapshot) -> String {
        switch account.status {
        case .loginRequired:
            return "需要重新登录小米账号"
        case .failed:
            return "套餐额度暂不可用"
        case .stale:
            return "显示上次成功数据"
        case .ready:
            return "等待额度刷新"
        }
    }

    private func accountFallbackPrimaryText(for account: QuotaAccountRowSnapshot) -> String {
        switch account.status {
        case .loginRequired:
            return "未登录"
        case .failed:
            return "刷新失败"
        case .stale:
            return "显示上次成功数据"
        case .ready:
            return "等待刷新"
        }
    }

    private func accountCardBackgroundColor(for account: QuotaAccountRowSnapshot) -> Color {
        switch account.status {
        case .loginRequired, .failed:
            return Color.orange.opacity(0.08)
        case .stale:
            return Color.primary.opacity(0.05)
        case .ready:
            return Color.primary.opacity(0.035)
        }
    }

    private func accountProgressColor(for riskLevel: QuotaProgressRiskLevel) -> Color {
        switch riskLevel {
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
