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

            Section("账号与来源") {
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
                Text("你可以决定展示哪些 agent / account 的 usage 统计；关闭后不会显示在主界面中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(EntitlementPreferences.descriptorTargets(providerPreferences: appState.providerPreferences)) { descriptor in
                Section(sectionTitle(for: descriptor)) {
                    Picker("来源", selection: selectedSourceBinding(for: descriptor.targetID)) {
                        Text("未配置").tag(EntitlementSourceSelection.none)
                        if descriptor.supportsOfficial {
                            Text("官方登录态").tag(EntitlementSourceSelection.official)
                        }
                        Text("第三方 API").tag(EntitlementSourceSelection.thirdParty)
                    }
                    .pickerStyle(.segmented)

                    switch EntitlementPreferences.selectedSourceBindingValue(for: descriptor.targetID) {
                    case .official:
                        Text(officialDescription(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .thirdParty:
                        TextField("Quota URL", text: bridgeEndpointBinding(for: descriptor.targetID))
                            .textFieldStyle(.roundedBorder)
                        SecureField("API Key", text: bridgeAPIKeyBinding(for: descriptor.targetID))
                            .textFieldStyle(.roundedBorder)
                        Text(bridgeDescription(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .none:
                        Text("此目标当前未配置套餐额度来源。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = appState.entitlementSummariesByTarget[descriptor.id] {
                        QuotaSummarySection(summary: summary)
                    }

                    Button("立即刷新") {
                        Task { await appState.refresh() }
                    }
                    .disabled(appState.isLoading)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func sectionTitle(for descriptor: EntitlementTargetDescriptor) -> String {
        descriptor.targetID == .overview ? "总览套餐额度" : "\(descriptor.name) 套餐额度"
    }

    private func officialDescription(for descriptor: EntitlementTargetDescriptor) -> String {
        if descriptor.supportsOfficial {
            return "已为 \(descriptor.name) 选择官方登录态。V1 仅保存选择并展示待接入状态，不会自动回退到第三方额度。"
        }
        return "该目标当前不支持官方套餐额度来源。"
    }

    private func bridgeDescription(for descriptor: EntitlementTargetDescriptor) -> String {
        descriptor.targetID == .overview
            ? "总览可绑定聚合平台的共享额度来源；其配置将优先于派生兜底摘要。"
            : "每个 provider 只能选择一个额度来源。第三方 API 会作为该 tab 的唯一套餐真值。"
    }

    private func selectedSourceBinding(for targetID: EntitlementTargetID) -> Binding<EntitlementSourceSelection> {
        Binding(
            get: { EntitlementPreferences.selectedSourceBindingValue(for: targetID) },
            set: { newValue in
                EntitlementPreferences.setSelectedSource(newValue, for: targetID)
                Task { await appState.refresh() }
            }
        )
    }

    private func bridgeEndpointBinding(for targetID: EntitlementTargetID) -> Binding<String> {
        Binding(
            get: { EntitlementPreferences.bridgeEndpointRaw(for: targetID) },
            set: { EntitlementPreferences.setBridgeEndpointRaw($0, for: targetID) }
        )
    }

    private func bridgeAPIKeyBinding(for targetID: EntitlementTargetID) -> Binding<String> {
        Binding(
            get: { EntitlementPreferences.bridgeAPIKey(for: targetID) },
            set: { EntitlementPreferences.setBridgeAPIKey($0, for: targetID) }
        )
    }
}
