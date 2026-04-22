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
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
