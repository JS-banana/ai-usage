import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(LaifuyouQuotaConfiguration.apiKeyDefaultsKey) private var quotaAPIKey = ""
    @AppStorage(LaifuyouQuotaConfiguration.endpointURLDefaultsKey) private var quotaEndpointURL = ""

    var body: some View {
        Form {
            Section("当前状态") {
                LabeledContent("最近状态", value: appState.statusMessage)
                if let lastRefresh = appState.lastRefresh {
                    LabeledContent("最近刷新", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                }
                if let selected = appState.selectedPanel {
                    LabeledContent("当前来源", value: selected.name)
                }
                LabeledContent("菜单栏摘要", value: appState.menuBarSummary.subtitle)
            }

            Section("账号与来源") {
                ForEach(appState.providerPreferences) { preference in
                    Toggle(isOn: Binding(
                        get: { appState.isProviderEnabled(preference.id) },
                        set: { appState.setProviderEnabled(preference.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(preference.name)
                                    .font(.body.weight(.medium))
                                if preference.supportsQuota {
                                    Text("Quota")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(preference.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                Text("你可以决定展示哪些 agent / account 的 usage 统计；关闭后不会显示在主界面中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quota 服务（分组总额度）") {
                TextField("Quota URL", text: $quotaEndpointURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $quotaAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("只需提供完整的 Quota URL 和 API Key；不再单独输入 group。项目源码不会内置真实 token / bearer。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("立即刷新") {
                    Task { await appState.refresh() }
                }
                .disabled(appState.isLoading)
            }

            Section("Quota 总额度预览") {
                QuotaSummarySection(summary: appState.groupQuotaSummary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
