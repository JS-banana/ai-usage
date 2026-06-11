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
    }

    private func quotaVendorGroup(_ group: QuotaVendorGroupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let summary = group.summary, summary.status != .unconfigured {
                QuotaSummarySection(summary: summary, compact: true)
            }

            VStack(spacing: 0) {
                ForEach(group.accounts) { account in
                    VStack(alignment: .leading, spacing: 6) {
                        quotaAccountRow(account)
                        if let summary = account.summary, summary.status != .unconfigured {
                            QuotaSummarySection(summary: summary, compact: true)
                                .padding(.bottom, 6)
                        }
                    }
                    if account.id != group.accounts.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func quotaAccountRow(_ account: QuotaAccountRowSnapshot) -> some View {
        HStack(spacing: 8) {
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
            Spacer()
            if account.planName.isEmpty == false {
                Text(account.planName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            if account.status != .ready {
                Text(statusText(account.status))
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(.vertical, 7)
    }

    private func statusText(_ status: QuotaAccountStatus) -> String {
        switch status {
        case .ready:
            return "ready"
        case .loginRequired:
            return "login required"
        }
    }
}
