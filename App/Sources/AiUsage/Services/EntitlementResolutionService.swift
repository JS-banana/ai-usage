import Foundation

final class EntitlementResolutionService: @unchecked Sendable {
    private let thirdPartyService: LaifuyouQuotaService
    private let officialProbe: OfficialEntitlementProbe
    private let mimoQuota: MiMoQuotaService?
    private let userDefaults: UserDefaults

    init(
        thirdPartyService: LaifuyouQuotaService,
        officialProbe: OfficialEntitlementProbe = OfficialEntitlementProbe(),
        mimoQuota: MiMoQuotaService? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.thirdPartyService = thirdPartyService
        self.officialProbe = officialProbe
        self.mimoQuota = mimoQuota
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

    func resolveSummary(
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
        case .mimo:
            guard let mimoQuota else {
                return makeUnconfiguredSummary(for: descriptor)
            }
            let accounts = EntitlementPreferences.mimoAccounts(userDefaults: userDefaults)
            guard !accounts.isEmpty else {
                return makeUnconfiguredSummary(for: descriptor)
            }

            var tokens: [UUID: MiMoServiceToken] = [:]
            for account in accounts {
                if let token = EntitlementPreferences.mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) {
                    tokens[account.id] = token
                }
            }

            guard !tokens.isEmpty else {
                return makeMiMoLoginRequiredSummary(for: descriptor)
            }

            let results = await mimoQuota.fetchAll(
                tokens: tokens,
                targetID: descriptor.targetID,
                title: descriptor.name,
                now: now
            )

            return aggregateMiMoResults(
                results: results,
                descriptor: descriptor,
                now: now
            )
        }
    }

    private func aggregateMiMoResults(
        results: [UUID: AccountFetchResult],
        descriptor: EntitlementTargetDescriptor,
        now: Date
    ) -> EntitlementSummarySnapshot {
        let successful = results.values.filter { $0.snapshot != nil }
        guard !successful.isEmpty else {
            let firstError = results.values.first?.error
            if let error = firstError as? MiMoQuotaService.QuotaError,
               case .unauthorized = error {
                return makeMiMoLoginRequiredSummary(for: descriptor)
            }
            return makeFailedSummary(for: descriptor, error: firstError ?? MiMoSSOAuthService.AuthError.invalidCredentials)
        }

        let totalPlanUsed = successful.reduce(0) { $0 + $1.planUsed }
        let totalPlanLimit = successful.reduce(0) { $0 + $1.planLimit }
        let totalCompensationUsed = successful.reduce(0) { $0 + $1.compensationUsed }
        let totalCompensationLimit = successful.reduce(0) { $0 + $1.compensationLimit }
        let earliestExpiry = successful.compactMap(\.expiresAt).min()

        let planProgress = totalPlanLimit > 0 ? Double(totalPlanUsed) / Double(totalPlanLimit) : 0
        let compensationProgress = totalCompensationLimit > 0 ? Double(totalCompensationUsed) / Double(totalCompensationLimit) : 0

        let targetID = descriptor.targetID
        let primaryWindow = EntitlementWindowSnapshot(
            id: "\(targetID.storageKey)-mimo-primary",
            title: "套餐总额度",
            primaryText: percentageText(planProgress),
            secondaryText: tokenUsageText(used: totalPlanUsed, limit: totalPlanLimit),
            footnoteText: expiryText(earliestExpiry),
            progress: planProgress
        )

        let secondaryWindow: EntitlementWindowSnapshot
        if totalCompensationLimit > 0 {
            secondaryWindow = EntitlementWindowSnapshot(
                id: "\(targetID.storageKey)-mimo-compensation",
                title: "补偿额度",
                primaryText: percentageText(compensationProgress),
                secondaryText: tokenUsageText(used: totalCompensationUsed, limit: totalCompensationLimit),
                footnoteText: expiryText(earliestExpiry),
                progress: compensationProgress
            )
        } else {
            secondaryWindow = .hidden(id: "\(targetID.storageKey)-mimo-compensation")
        }

        return EntitlementSummarySnapshot(
            targetID: targetID,
            title: descriptor.name,
            message: "",
            updatedAt: now,
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )
    }

    private func percentageText(_ progress: Double) -> String {
        "已用 \(min(max(progress, 0), 1).formatted(.percent.precision(.fractionLength(0))))"
    }

    private func tokenUsageText(used: Int, limit: Int) -> String {
        "\(tokenText(used)) / \(tokenText(limit)) token"
    }

    private func tokenText(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 100_000_000 {
            return "\(trimmed(Double(value) / 100_000_000))亿"
        }
        if absolute >= 10_000 {
            return "\(trimmed(Double(value) / 10_000))万"
        }
        return value.formatted()
    }

    private func trimmed(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func expiryText(_ date: Date?) -> String {
        guard let date else { return "到期时间未返回" }
        return "到期 \(date.formatted(date: .numeric, time: .omitted))"
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

    private func makeMiMoLoginRequiredSummary(for descriptor: EntitlementTargetDescriptor) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot.placeholder(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "MiMo 登录态不可用。",
            status: .failed,
            sourceKind: .mimo,
            primaryText: "需要重新登录",
            secondaryText: "请点击添加账号完成小米官方登录",
            footnote: "不会在后台使用账号密码重试，避免触发风控"
        )
    }

    private func makeFailedSummary(for descriptor: EntitlementTargetDescriptor, error: any Error) -> EntitlementSummarySnapshot {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return EntitlementSummarySnapshot.placeholder(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "套餐额度刷新失败。",
            status: .failed,
            sourceKind: descriptor.id == "mimo" ? .mimo : .thirdParty,
            primaryText: "刷新失败",
            secondaryText: detail.isEmpty ? "未知错误" : detail,
            footnote: "请检查 URL / API Key 或稍后重试"
        )
    }
}
