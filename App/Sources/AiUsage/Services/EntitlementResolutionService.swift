import Foundation
import Domain

final class EntitlementResolutionService: @unchecked Sendable {
    private let thirdPartyService: LaifuyouQuotaService
    private let officialProbe: OfficialEntitlementProbe
    private let mimoQuota: MiMoQuotaService?
    private let quotaSnapshotStore: (any QuotaSnapshotStoring)?
    private let userDefaults: UserDefaults

    init(
        thirdPartyService: LaifuyouQuotaService,
        officialProbe: OfficialEntitlementProbe = OfficialEntitlementProbe(),
        mimoQuota: MiMoQuotaService? = nil,
        quotaSnapshotStore: (any QuotaSnapshotStoring)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.thirdPartyService = thirdPartyService
        self.officialProbe = officialProbe
        self.mimoQuota = mimoQuota
        self.quotaSnapshotStore = quotaSnapshotStore
        self.userDefaults = userDefaults
    }

    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        trigger: ImportTrigger = .manual,
        now: Date = Date()
    ) async -> [String: EntitlementSummarySnapshot] {
        var summaries: [String: EntitlementSummarySnapshot] = [:]

        for descriptor in descriptors {
            let configuration = EntitlementPreferences.configuration(for: descriptor.targetID, userDefaults: userDefaults)
            summaries[descriptor.id] = await resolveSummary(for: descriptor, configuration: configuration, trigger: trigger, now: now)
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
        trigger: ImportTrigger = .manual,
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

            if trigger != .manual,
               let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
                return fallback
            }

            var tokens: [UUID: MiMoServiceToken] = [:]
            for account in accounts {
                if let token = EntitlementPreferences.mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) {
                    tokens[account.id] = token
                }
            }

            if tokens.isEmpty, let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
                return fallback
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

            return await aggregateMiMoResults(
                results: results,
                accounts: accounts,
                descriptor: descriptor,
                now: now
            )
        }
    }

    private func aggregateMiMoResults(
        results: [UUID: AccountFetchResult],
        accounts: [MiMoAccount],
        descriptor: EntitlementTargetDescriptor,
        now: Date
    ) async -> EntitlementSummarySnapshot {
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let successfulByAccount = results.compactMap { accountID, result -> (UUID, MiMoAccount, AccountFetchResult)? in
            guard result.snapshot != nil, let account = accountByID[accountID] else { return nil }
            return (accountID, account, result)
        }
        guard !successfulByAccount.isEmpty else {
            let firstError = results.values.first?.error
            if let error = firstError as? MiMoQuotaService.QuotaError,
               case .unauthorized = error {
                if let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
                    return fallback
                }
                return makeMiMoLoginRequiredSummary(for: descriptor)
            }
            if let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
                return fallback
            }
            return makeFailedSummary(for: descriptor, error: firstError ?? MiMoSSOAuthService.AuthError.invalidCredentials)
        }

        let successful = successfulByAccount.map(\.2)
        let failedCount = max(0, accounts.count - successfulByAccount.count)
        let isPartial = failedCount > 0
        let totalPlanUsed = successful.reduce(0) { $0 + $1.planUsed }
        let totalPlanLimit = successful.reduce(0) { $0 + $1.planLimit }
        let totalCompensationUsed = successful.reduce(0) { $0 + $1.compensationUsed }
        let totalCompensationLimit = successful.reduce(0) { $0 + $1.compensationLimit }
        let earliestExpiry = successful.compactMap(\.expiresAt).min()

        let totalUsed = totalPlanUsed + totalCompensationUsed
        let totalLimit = totalPlanLimit + totalCompensationLimit
        let planProgress = totalLimit > 0 ? Double(totalUsed) / Double(totalLimit) : 0

        let targetID = descriptor.targetID
        let primaryWindow = EntitlementWindowSnapshot(
            id: "\(targetID.storageKey)-mimo-primary",
            title: "套餐总额度",
            detailText: tokenUsageDetailText(used: totalUsed, limit: totalLimit),
            primaryText: usedPercentText(planProgress),
            secondaryText: compactDateText(earliestExpiry),
            footnoteText: "",
            progress: planProgress
        )

        let secondaryWindow = EntitlementWindowSnapshot.hidden(id: "\(targetID.storageKey)-mimo-compensation")

        let summary = EntitlementSummarySnapshot(
            targetID: targetID,
            title: descriptor.name,
            message: isPartial ? "部分账号额度刷新失败，显示已成功账号的数据。" : "",
            updatedAt: now,
            status: isPartial ? .stale : .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            menuBarProgress: planProgress
        )
        if isPartial == false {
            await persistMiMoSnapshotIfPossible(
                totalUsed: totalUsed,
                totalLimit: totalLimit,
                expiresAt: earliestExpiry,
                capturedAt: now
            )
        }
        return summary
    }

    private func persistMiMoSnapshotIfPossible(
        totalUsed: Int,
        totalLimit: Int,
        expiresAt: Date?,
        capturedAt: Date
    ) async {
        guard let quotaSnapshotStore else { return }
        let accountID = MiMoAggregateSnapshotAccount.accountID
        let snapshotID = StableQuotaSnapshotID.make(providerID: "mimo", accountID: accountID, capturedAt: capturedAt)
        let providerAccount = ProviderAccount(
            id: accountID,
            providerID: "mimo",
            accountLabel: "MiMo aggregate",
            backendLabel: "xiaomi",
            createdAt: capturedAt,
            updatedAt: capturedAt
        )
        let snapshot = QuotaSnapshot(
            id: snapshotID,
            accountID: accountID,
            refreshRunID: nil,
            capturedAt: capturedAt,
            freshnessDate: capturedAt,
            isStale: false
        )
        let window = AllowanceWindow(
            id: "\(snapshotID)-token-plan",
            snapshotID: snapshotID,
            kind: .monthly,
            used: Double(totalUsed),
            limit: Double(totalLimit),
            remaining: Double(max(0, totalLimit - totalUsed)),
            resetsAt: expiresAt
        )
        try? await quotaSnapshotStore.persistQuotaSnapshot(
            ProviderQuotaSnapshot(account: providerAccount, snapshot: snapshot, windows: [window])
        )
    }

    private func latestCachedMiMoSummary(
        accounts: [MiMoAccount],
        descriptor: EntitlementTargetDescriptor
    ) async -> EntitlementSummarySnapshot? {
        guard let quotaSnapshotStore else { return nil }
        if let cached = try? await quotaSnapshotStore.latestQuotaSnapshot(
            providerID: "mimo",
            accountID: MiMoAggregateSnapshotAccount.accountID
        ), let summary = cachedMiMoSummary(cached, descriptor: descriptor) {
            return summary
        }
        for account in accounts {
            guard let cached = try? await quotaSnapshotStore.latestQuotaSnapshot(
                providerID: "mimo",
                accountID: account.id.uuidString
            ) else {
                continue
            }
            if let summary = cachedMiMoSummary(cached, descriptor: descriptor) {
                return summary
            }
        }
        return nil
    }

    private func cachedMiMoSummary(
        _ cached: ProviderQuotaSnapshot,
        descriptor: EntitlementTargetDescriptor
    ) -> EntitlementSummarySnapshot? {
        guard let window = cached.windows.first(where: { $0.kind == .monthly }) ?? cached.windows.first else {
            return nil
        }
        let limit = Int(window.limit ?? (window.used + (window.remaining ?? 0)))
        let used = Int(window.used)
        let progress = limit > 0 ? Double(used) / Double(limit) : 0
        let primaryWindow = EntitlementWindowSnapshot(
            id: "\(descriptor.targetID.storageKey)-mimo-primary",
            title: "套餐总额度",
            detailText: tokenUsageDetailText(used: used, limit: limit),
            primaryText: usedPercentText(progress),
            secondaryText: compactDateText(window.resetsAt),
            footnoteText: "上次成功刷新 \(cached.snapshot.freshnessDate.formatted(date: .numeric, time: .shortened))",
            progress: progress
        )
        return EntitlementSummarySnapshot(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "MiMo 额度刷新失败，显示上次成功数据。",
            updatedAt: cached.snapshot.freshnessDate,
            status: .stale,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: primaryWindow,
            secondaryWindow: .hidden(id: "\(descriptor.targetID.storageKey)-mimo-compensation"),
            menuBarProgress: progress
        )
    }

    private func usedPercentText(_ progress: Double) -> String {
        "\(min(max(progress, 0), 1).formatted(.percent.precision(.fractionLength(0)))) used"
    }

    private func trimmed(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func compactDateText(_ date: Date?) -> String {
        guard let date else { return "expires unknown" }
        return "expires \(date.formatted(date: .numeric, time: .omitted))"
    }

    private func tokenUsageDetailText(used: Int, limit: Int) -> String {
        "\(compactTokenText(used)) / \(compactTokenText(limit)) tokens"
    }

    private func compactTokenText(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000_000 {
            return "\(trimmed(Double(value) / 1_000_000_000))B"
        }
        if absolute >= 1_000_000 {
            return "\(trimmed(Double(value) / 1_000_000))M"
        }
        if absolute >= 1_000 {
            return "\(trimmed(Double(value) / 1_000))K"
        }
        return value.formatted()
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
            secondaryWindow: chosen.secondaryWindow,
            extraWindows: chosen.extraWindows,
            menuBarProgress: chosen.menuBarProgress
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
        EntitlementSummarySnapshot(
            targetID: descriptor.targetID,
            title: descriptor.name,
            message: "",
            updatedAt: nil,
            status: .failed,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: EntitlementWindowSnapshot(
                id: "\(descriptor.targetID.storageKey)-mimo-login-required",
                title: "",
                primaryText: "需要重新登录小米账号",
                secondaryText: "",
                footnoteText: "",
                progress: nil
            ),
            secondaryWindow: .hidden(id: "\(descriptor.targetID.storageKey)-mimo-login-required-hidden")
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

private enum StableQuotaSnapshotID {
    static func make(providerID: String, accountID: String, capturedAt: Date) -> String {
        let timestamp = Int(capturedAt.timeIntervalSince1970 * 1000)
        return "\(providerID)-\(accountID)-\(timestamp)"
    }
}

private enum MiMoAggregateSnapshotAccount {
    static let accountID = "mimo-aggregate"
}
