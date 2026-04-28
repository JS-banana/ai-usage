import Foundation

actor EntitlementResolutionService {
    private let thirdPartyService: LaifuyouQuotaService
    private let officialProbe: OfficialEntitlementProbe
    private let userDefaults: UserDefaults

    init(
        thirdPartyService: LaifuyouQuotaService,
        officialProbe: OfficialEntitlementProbe = OfficialEntitlementProbe(),
        userDefaults: UserDefaults = .standard
    ) {
        self.thirdPartyService = thirdPartyService
        self.officialProbe = officialProbe
        self.userDefaults = userDefaults
    }

    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        now: Date = Date()
    ) async -> [String: EntitlementSummarySnapshot] {
        var summaries: [String: EntitlementSummarySnapshot] = [:]

        for descriptor in descriptors {
            let configuration = EntitlementPreferences.configuration(for: descriptor.targetID, userDefaults: userDefaults)
            summaries[descriptor.id] = await resolveSummary(for: descriptor, configuration: configuration, now: now)
        }

        summaries[EntitlementTargetID.overview.storageKey] = deriveOverviewSummary(
            explicitOverview: summaries[EntitlementTargetID.overview.storageKey],
            providerDescriptors: descriptors.filter { if case .provider = $0.targetID { return true } else { return false } },
            visibleProviderIDs: visibleProviderIDs,
            summaries: summaries
        )

        return summaries
    }

    private func resolveSummary(
        for descriptor: EntitlementTargetDescriptor,
        configuration: EntitlementTargetConfiguration,
        now: Date
    ) async -> EntitlementSummarySnapshot {
        switch configuration.selectedSource {
        case .none:
            return makeUnconfiguredSummary(for: descriptor)
        case .official:
            if descriptor.supportsOfficial == false {
                return makeUnavailableOfficialSummary(for: descriptor)
            }
            return await officialProbe.fetchSummary(for: descriptor)
        case .thirdParty:
            guard let bridgeConfiguration = configuration.bridgeConfiguration else {
                return makeUnconfiguredSummary(for: descriptor)
            }
            do {
                return try await thirdPartyService.fetch(
                    configuration: bridgeConfiguration,
                    targetID: descriptor.targetID,
                    title: descriptor.name,
                    now: now
                )
            } catch {
                return makeFailedSummary(for: descriptor, error: error)
            }
        }
    }

    private func deriveOverviewSummary(
        explicitOverview: EntitlementSummarySnapshot?,
        providerDescriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        summaries: [String: EntitlementSummarySnapshot]
    ) -> EntitlementSummarySnapshot {
        if let explicitOverview,
           explicitOverview.status == .ready || explicitOverview.status == .stale || explicitOverview.status == .failed {
            return explicitOverview
        }

        let candidates = providerDescriptors
            .filter { visibleProviderIDs.contains($0.id) }
            .compactMap { summaries[$0.id] }

        guard let chosen = candidates.max(by: isLowerPriority(_:than:)) else {
            return EntitlementSummarySnapshot.placeholder(
                targetID: .overview,
                title: "总览套餐",
                message: "未配置总览套餐额度；配置 provider 或总览来源后会显示汇总。",
                status: .unconfigured,
                sourceKind: nil,
                provenance: .derived,
                primaryText: "未配置",
                secondaryText: "暂无可用额度来源",
                footnote: "可在设置中为总览或 provider 配置套餐来源"
            )
        }

        return EntitlementSummarySnapshot(
            targetID: .overview,
            title: "总览套餐",
            message: "未配置总览来源，当前显示风险最高的 provider 额度摘要。",
            updatedAt: chosen.updatedAt,
            status: chosen.status,
            sourceKind: chosen.sourceKind,
            provenance: .derived,
            derivedFromTitle: chosen.title,
            primaryWindow: chosen.primaryWindow,
            secondaryWindow: chosen.secondaryWindow
        )
    }

    private func isLowerPriority(_ lhs: EntitlementSummarySnapshot, than rhs: EntitlementSummarySnapshot) -> Bool {
        let leftScore = priorityScore(for: lhs)
        let rightScore = priorityScore(for: rhs)
        if leftScore != rightScore {
            return leftScore < rightScore
        }
        return lhs.title > rhs.title
    }

    private func priorityScore(for summary: EntitlementSummarySnapshot) -> Int {
        let statusWeight: Int
        switch summary.status {
        case .failed:
            statusWeight = 600
        case .stale:
            statusWeight = 500
        case .ready:
            statusWeight = 400
        case .configuredNonlive:
            statusWeight = 300
        case .unconfigured:
            statusWeight = 200
        case .unavailable:
            statusWeight = 100
        }
        let primary = Int((summary.primaryWindow.progress ?? 0) * 1000)
        let secondary = Int((summary.secondaryWindow.progress ?? 0) * 1000)
        let windowWeight = max(primary * 2, secondary * 2 - (primary == secondary ? 1 : 0))
        return statusWeight + windowWeight
    }

    private func makeUnconfiguredSummary(for descriptor: EntitlementTargetDescriptor) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot.placeholder(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "未配置套餐额度来源。",
            status: .unconfigured,
            sourceKind: nil,
            primaryText: "未配置",
            secondaryText: "选择官方或第三方来源",
            footnote: "设置后可随 active tab 同步展示"
        )
    }

    private func makeUnavailableOfficialSummary(for descriptor: EntitlementTargetDescriptor) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot.placeholder(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "该目标暂不支持官方套餐额度来源。",
            status: .unavailable,
            sourceKind: .official,
            primaryText: "不可用",
            secondaryText: "请改用第三方 API",
            footnote: "V1 仅 Codex / Claude 允许官方来源占位"
        )
    }

    private func makeFailedSummary(for descriptor: EntitlementTargetDescriptor, error: any Error) -> EntitlementSummarySnapshot {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return EntitlementSummarySnapshot.placeholder(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "套餐额度刷新失败。",
            status: .failed,
            sourceKind: .thirdParty,
            primaryText: "刷新失败",
            secondaryText: detail.isEmpty ? "未知错误" : detail,
            footnote: "请检查 URL / API Key 或稍后重试"
        )
    }
}
