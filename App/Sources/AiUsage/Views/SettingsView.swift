import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("当前状态") {
                LabeledContent("最近状态", value: appState.statusMessage)
                if let lastRefresh = appState.lastRefresh {
                    LabeledContent("最近刷新", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                }
                if let selected = appState.selectedPanel {
                    LabeledContent("当前来源", value: selected.name)
                } else {
                    LabeledContent("当前来源", value: "总览")
                }
                LabeledContent("菜单栏摘要", value: appState.menuBarSummary.subtitle)
            }

            Section("Agent 显示") {
                ForEach(appState.providerPreferences) { preference in
                    Toggle(isOn: Binding(
                        get: { appState.isProviderEnabled(preference.id) },
                        set: { appState.setProviderEnabled(preference.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preference.name)
                                .font(.body.weight(.medium))
                            Text(preference.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                Text("控制哪些本机 agent 参与本机 usage 统计和 tab 展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
