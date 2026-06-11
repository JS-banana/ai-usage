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
            let resolved = await resolveSummaryBundle(for: descriptor, configuration: configuration, trigger: trigger, now: now)
            summaries[descriptor.id] = resolved.summary
            summaries.merge(resolved.accountSummaries) { _, new in new }
        }

        summaries[EntitlementTargetID.overview.storageKey] = deriveOverviewSummary(
            explicitOverview: summaries[EntitlementTargetID.overview.storageKey],
            providerDescriptors: descriptors.filter { if case .provider = $0.targetID { return true } else { return false } },
            visibleProviderIDs: visibleProviderIDs,
            summaries: summaries
        )

        return summaries
    }

    private struct SummaryBundle: Sendable {
        let summary: EntitlementSummarySnapshot
        let accountSummaries: [String: EntitlementSummarySnapshot]
    }

    private func resolveSummaryBundle(
        for descriptor: EntitlementTargetDescriptor,
        configuration: EntitlementTargetConfiguration,
        trigger: ImportTrigger,
        now: Date
    ) async -> SummaryBundle {
        guard configuration.selectedSource == .mimo else {
            return SummaryBundle(
                summary: await resolveSummary(for: descriptor, configuration: configuration, trigger: trigger, now: now),
                accountSummaries: [:]
            )
        }
        guard let mimoQuota else {
            return SummaryBundle(summary: makeUnconfiguredSummary(for: descriptor), accountSummaries: [:])
        }
        let accounts = EntitlementPreferences.mimoAccounts(userDefaults: userDefaults)
        guard !accounts.isEmpty else {
            return SummaryBundle(summary: makeUnconfiguredSummary(for: descriptor), accountSummaries: [:])
        }

        if trigger != .manual,
           let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
            return SummaryBundle(
                summary: fallback,
                accountSummaries: await latestCachedMiMoAccountSummaries(accounts: accounts, descriptor: descriptor)
            )
        }

        var tokens: [UUID: MiMoServiceToken] = [:]
        for account in accounts {
            if let token = EntitlementPreferences.mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) {
                tokens[account.id] = token
            }
        }

        if tokens.isEmpty, let fallback = await latestCachedMiMoSummary(accounts: accounts, descriptor: descriptor) {
            return SummaryBundle(
                summary: fallback,
                accountSummaries: await latestCachedMiMoAccountSummaries(accounts: accounts, descriptor: descriptor)
            )
        }

        guard !tokens.isEmpty else {
            return SummaryBundle(summary: makeMiMoLoginRequiredSummary(for: descriptor), accountSummaries: [:])
        }

        let results = await mimoQuota.fetchAll(
            tokens: tokens,
            targetID: descriptor.targetID,
            title: descriptor.name,
            now: now
        )
        let summary = await aggregateMiMoResults(
            results: results,
            accounts: accounts,
            descriptor: descriptor,
            now: now
        )
        var accountSummaries = perAccountMiMoSummaries(results: results, accounts: accounts)
        if accountSummaries.isEmpty {
            accountSummaries = await latestCachedMiMoAccountSummaries(accounts: accounts, descriptor: descriptor)
        }
        return SummaryBundle(summary: summary, accountSummaries: accountSummaries)
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

    private func perAccountMiMoSummaries(
        results: [UUID: AccountFetchResult],
        accounts: [MiMoAccount]
    ) -> [String: EntitlementSummarySnapshot] {
        var accountSummaries: [String: EntitlementSummarySnapshot] = [:]
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        for (accountID, result) in results {
            guard var snapshot = result.snapshot, let account = accountByID[accountID] else { continue }
            snapshot = EntitlementSummarySnapshot(
                targetID: snapshot.targetID,
                title: displayLabel(for: account, profile: result.profile),
                message: snapshot.message,
                updatedAt: snapshot.updatedAt,
                status: snapshot.status,
                sourceKind: snapshot.sourceKind,
                provenance: snapshot.provenance,
                derivedFromTitle: snapshot.derivedFromTitle,
                primaryWindow: accountQuotaWindow(from: snapshot.primaryWindow),
                secondaryWindow: snapshot.secondaryWindow,
                extraWindows: snapshot.extraWindows,
                menuBarProgress: snapshot.menuBarProgress
            )
            accountSummaries[QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)] = snapshot
        }
        return accountSummaries
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
            detailText: "",
            primaryText: usedPercentText(planProgress),
            secondaryText: "",
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
        persistMiMoDisplayMetadata(successfulByAccount)
        await persistMiMoSnapshotsIfPossible(
            successfulByAccount: successfulByAccount,
            allAccountCount: accounts.count,
            totalUsed: totalUsed,
            totalLimit: totalLimit,
            aggregateExpiresAt: earliestExpiry,
            capturedAt: now,
            isPartial: isPartial
        )
        return summary
    }

    private func persistMiMoDisplayMetadata(_ successfulAccounts: [(UUID, MiMoAccount, AccountFetchResult)]) {
        for (accountID, _, result) in successfulAccounts {
            EntitlementPreferences.updateMiMoAccountDisplayMetadata(
                id: accountID,
                profile: result.profile,
                planName: result.planName,
                userDefaults: userDefaults
            )
        }
    }

    private func persistMiMoSnapshotsIfPossible(
        successfulByAccount: [(UUID, MiMoAccount, AccountFetchResult)],
        allAccountCount: Int,
        totalUsed: Int,
        totalLimit: Int,
        aggregateExpiresAt: Date?,
        capturedAt: Date,
        isPartial: Bool
    ) async {
        guard let quotaSnapshotStore else { return }
        for (accountID, account, result) in successfulByAccount {
            guard result.totalLimit > 0 else { continue }
            let accountCapturedAt = result.capturedAt ?? capturedAt
            let snapshotID = StableQuotaSnapshotID.make(
                providerID: "mimo",
                accountID: accountID.uuidString,
                capturedAt: accountCapturedAt
            )
            let providerAccount = ProviderAccount(
                id: accountID.uuidString,
                providerID: "mimo",
                accountLabel: displayLabel(for: account, profile: result.profile),
                backendLabel: "xiaomi",
                createdAt: accountCapturedAt,
                updatedAt: accountCapturedAt
            )
            let snapshot = QuotaSnapshot(
                id: snapshotID,
                accountID: accountID.uuidString,
                refreshRunID: nil,
                capturedAt: accountCapturedAt,
                freshnessDate: accountCapturedAt,
                isStale: false
            )
            let window = AllowanceWindow(
                id: "\(snapshotID)-token-plan",
                snapshotID: snapshotID,
                kind: .monthly,
                used: Double(result.totalUsed),
                limit: Double(result.totalLimit),
                remaining: Double(max(0, result.totalLimit - result.totalUsed)),
                resetsAt: result.expiresAt
            )
            try? await quotaSnapshotStore.persistQuotaSnapshot(
                ProviderQuotaSnapshot(account: providerAccount, snapshot: snapshot, windows: [window])
            )
        }

        guard allAccountCount > 1, isPartial == false else { return }
        await persistMiMoAggregateSnapshotIfPossible(
            totalUsed: totalUsed,
            totalLimit: totalLimit,
            expiresAt: aggregateExpiresAt,
            capturedAt: capturedAt
        )
    }

    private func displayLabel(for account: MiMoAccount, profile: MiMoAccountProfile?) -> String {
        for value in [
            profile?.email,
            profile?.platformEmail,
            profile?.phone,
            profile?.userName,
            profile?.nickName,
            account.email,
            account.platformEmail,
            account.phone,
            account.displayName
        ] {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, isTechnicalMiMoID(trimmed) == false {
                return trimmed
            }
        }
        return "MiMo Account"
    }

    private func isTechnicalMiMoID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^MiMo\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private func persistMiMoAggregateSnapshotIfPossible(
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
        if accounts.count == 1, let account = accounts.first {
            if let cached = try? await quotaSnapshotStore.latestQuotaSnapshot(
                providerID: "mimo",
                accountID: account.id.uuidString
            ), let summary = cachedMiMoSummary(
                cached,
                descriptor: descriptor,
                title: displayLabel(for: account, profile: nil),
                windowTitle: "账号额度",
                includeUsageDetail: true
            ) {
                return summary
            }
        }
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

    private func latestCachedMiMoAccountSummaries(
        accounts: [MiMoAccount],
        descriptor: EntitlementTargetDescriptor
    ) async -> [String: EntitlementSummarySnapshot] {
        guard let quotaSnapshotStore else { return [:] }

        var summaries: [String: EntitlementSummarySnapshot] = [:]
        for account in accounts {
            guard let cached = try? await quotaSnapshotStore.latestQuotaSnapshot(
                providerID: "mimo",
                accountID: account.id.uuidString
            ), let summary = cachedMiMoSummary(
                cached,
                descriptor: descriptor,
                title: displayLabel(for: account, profile: nil),
                windowTitle: "账号额度",
                includeUsageDetail: true
            ) else {
                continue
            }
            summaries[QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: account.id)] = summary
        }
        return summaries
    }

    private func cachedMiMoSummary(
        _ cached: ProviderQuotaSnapshot,
        descriptor: EntitlementTargetDescriptor,
        title: String? = nil,
        windowTitle: String = "套餐总额度",
        includeUsageDetail: Bool = false
    ) -> EntitlementSummarySnapshot? {
        guard let window = cached.windows.first(where: { $0.kind == .monthly }) ?? cached.windows.first else {
            return nil
        }
        let limit = Int(window.limit ?? (window.used + (window.remaining ?? 0)))
        let used = Int(window.used)
        let progress = limit > 0 ? Double(used) / Double(limit) : 0
        let primaryWindow = EntitlementWindowSnapshot(
            id: "\(descriptor.targetID.storageKey)-mimo-primary",
            title: windowTitle,
            detailText: includeUsageDetail ? tokenUsageDetailText(used: used, limit: limit) : "",
            primaryText: usedPercentText(progress),
            secondaryText: includeUsageDetail ? compactDateText(window.resetsAt) : "",
            footnoteText: "显示上次成功数据 · \(cached.snapshot.freshnessDate.formatted(date: .numeric, time: .shortened))",
            progress: progress
        )
        return EntitlementSummarySnapshot(
            targetID: descriptor.targetID,
            title: title ?? descriptor.name,
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

    private func accountQuotaWindow(from window: EntitlementWindowSnapshot) -> EntitlementWindowSnapshot {
        EntitlementWindowSnapshot(
            id: window.id,
            title: "账号额度",
            detailText: window.detailText,
            primaryText: window.primaryText,
            secondaryText: window.secondaryText,
            footnoteText: window.footnoteText,
            progress: window.progress
        )
    }

    private func usedPercentText(_ progress: Double) -> String {
        "\(min(max(progress, 0), 1).formatted(.percent.precision(.fractionLength(0)))) used"
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
        return value.formatted()
    }

    private func trimmed(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
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
            .compactMap { summaries[$0.id] }
            .filter { $0.status != .unconfigured && $0.status != .unavailable }

        guard let chosen = candidates.max(by: isLowerPriority(_:than:)) else {
            return EntitlementSummarySnapshot.placeholder(
                targetID: .overview,
                title: "总览套餐",
                message: "未配置可用套餐额度；在额度 tab 添加账号后会显示汇总。",
                status: .unconfigured,
                sourceKind: nil,
                provenance: .derived,
                primaryText: "未配置",
                secondaryText: "暂无可用额度来源",
                footnote: "在额度 tab 管理账号"
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
            footnote: "在额度 tab 管理账号"
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
