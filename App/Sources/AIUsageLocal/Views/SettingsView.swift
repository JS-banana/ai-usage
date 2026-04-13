import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("产品定位") {
                LabeledContent("模式", value: "纯本地 / 无上传")
                LabeledContent("刷新策略", value: "自动发现 + 手动刷新")
                LabeledContent("首批支持", value: "Claude / Codex / OpenCode / Gemini")
            }

            Section("当前状态") {
                LabeledContent("最近状态", value: appState.statusMessage)
                if let lastRefresh = appState.lastRefresh {
                    LabeledContent("最近刷新", value: lastRefresh.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("后续规划") {
                Text("第二阶段将增加 FSEvents 自动监听、菜单栏模式、导出与更强的增量索引。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
