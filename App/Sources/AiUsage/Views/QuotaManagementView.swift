import SwiftUI

struct QuotaManagementView: View {
    let groups: [QuotaVendorGroupSnapshot]
    let selectedMenuBarTarget: QuotaMenuBarTargetPreference
    let setMenuBarTarget: (QuotaMenuBarTargetPreference) -> Void
    let refresh: () -> Void
    let addMiMoAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("菜单栏")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button {
                    setMenuBarTarget(.auto)
                } label: {
                    Label("Auto", systemImage: selectedMenuBarTarget == .auto ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新额度")
            }

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    setMenuBarTarget(group.menuBarTarget)
                } label: {
                    Image(systemName: selectedMenuBarTarget == group.menuBarTarget ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help("菜单栏显示 \(group.title)")
            }

            if group.summary.status != .unconfigured {
                QuotaSummarySection(summary: group.summary, compact: true)
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
                Button {
                    addMiMoAccount()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("添加账号")
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func quotaAccountRow(_ account: QuotaAccountRowSnapshot) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                    .font(.caption.weight(.medium))
                Text(account.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(statusText(account.status))
                .font(.caption2)
                .foregroundStyle(account.status == .ready ? Color.secondary : Color.orange)
            Button {
                setMenuBarTarget(account.menuBarTarget)
            } label: {
                Image(systemName: selectedMenuBarTarget == account.menuBarTarget ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help("菜单栏显示 \(account.title)")
        }
        .padding(.vertical, 7)
    }

    private func statusText(_ status: QuotaAccountStatus) -> String {
        switch status {
        case .ready:
            return "ready"
        case .loginRequired:
            return "login"
        }
    }
}
