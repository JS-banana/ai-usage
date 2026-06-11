import Foundation

enum QuotaAccountStatus: String, Hashable, Sendable {
    case ready
    case stale
    case failed
    case loginRequired
}

enum QuotaMenuBarTargetPreference: Hashable, Sendable {
    case auto
    case target(String)

    var storageValue: String {
        switch self {
        case .auto:
            return "auto"
        case .target(let storageKey):
            return storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    init(storageValue: String?) {
        let value = (storageValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "auto" {
            self = .auto
        } else {
            self = .target(value)
        }
    }
}

enum QuotaMenuBarTargetKey {
    static func account(providerID: String, accountID: UUID) -> String {
        "\(providerID):account:\(accountID.uuidString)"
    }
}

struct QuotaAccountRowSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let planName: String
    let status: QuotaAccountStatus
    let footerStatusText: String
    let summary: EntitlementSummarySnapshot?
}

struct QuotaVendorGroupSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: EntitlementSummarySnapshot?
    let accounts: [QuotaAccountRowSnapshot]
}

enum QuotaAccountReadModel {
    static func makeGroups(
        entitlementsByTarget: [String: EntitlementSummarySnapshot],
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [QuotaVendorGroupSnapshot] {
        let mimoAccounts = EntitlementPreferences.mimoAccountDisplayMirror(userDefaults: userDefaults)
        let accountsWithToken = EntitlementPreferences.mimoAccountIDsWithStoredToken(userDefaults: userDefaults)
        guard mimoAccounts.isEmpty == false || entitlementsByTarget["mimo"] != nil else {
            return []
        }
        let vendorSummary = mimoAccounts.count > 1
            ? (entitlementsByTarget["mimo"] ?? missingSummary(providerID: "mimo", title: "MiMo", sourceKind: .mimo))
            : nil

        return [
            QuotaVendorGroupSnapshot(
                id: "mimo",
                title: "MiMo",
                summary: vendorSummary,
                accounts: mimoAccounts.enumerated().map { index, account in
                    let accountTargetKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: account.id)
                    let summary = entitlementsByTarget[accountTargetKey]
                    let hasToken = accountsWithToken.contains(account.id)
                    let status = status(for: summary, hasToken: hasToken)
                    let title = title(for: account, index: index)
                    return QuotaAccountRowSnapshot(
                        id: accountTargetKey,
                        title: title,
                        subtitle: subtitle(for: account, title: title),
                        planName: planName(for: account),
                        status: status,
                        footerStatusText: footerStatusText(for: status, summary: summary, now: now),
                        summary: summary
                    )
                }
            )
        ]
    }

    private static func title(for account: MiMoAccount, index: Int) -> String {
        for value in [account.email, account.platformEmail] {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, isTechnicalMiMoID(trimmed) == false {
                return trimmed
            }
        }
        let phone = (account.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if phone.isEmpty == false {
            return phone
        }
        for value in [account.displayName, account.credentials.username] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, isTechnicalMiMoID(trimmed) == false {
                return trimmed
            }
        }
        return "账号 \(index + 1)"
    }

    private static func subtitle(for account: MiMoAccount, title: String) -> String {
        let username = account.credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.isEmpty == false, isTechnicalMiMoID(username) == false else { return "" }
        return title.localizedCaseInsensitiveContains(username) ? "" : username
    }

    private static func planName(for account: MiMoAccount) -> String {
        (account.planName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func status(for summary: EntitlementSummarySnapshot?, hasToken: Bool) -> QuotaAccountStatus {
        guard let summary else {
            return hasToken ? .failed : .loginRequired
        }
        switch summary.status {
        case .ready:
            return .ready
        case .stale:
            return .stale
        case .failed:
            return hasToken ? .failed : .loginRequired
        case .unconfigured, .configuredNonlive, .unavailable:
            return hasToken ? .failed : .loginRequired
        }
    }

    private static func footerStatusText(
        for status: QuotaAccountStatus,
        summary: EntitlementSummarySnapshot?,
        now: Date
    ) -> String {
        switch status {
        case .ready:
            return "updated \(relativeTimeText(for: summary?.updatedAt, now: now))"
        case .stale:
            return "last success \(relativeTimeText(for: summary?.updatedAt, now: now))"
        case .loginRequired:
            return "login required"
        case .failed:
            return "refresh failed"
        }
    }

    private static func relativeTimeText(for date: Date?, now: Date) -> String {
        guard let date else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func isTechnicalMiMoID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^MiMo\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private static func missingSummary(
        providerID: String,
        title: String,
        sourceKind: EntitlementSourceKind?
    ) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot.placeholder(
            targetID: .provider(providerID),
            title: title,
            message: "未配置套餐额度来源。",
            status: .unconfigured,
            sourceKind: sourceKind,
            primaryText: "未配置",
            secondaryText: "",
            footnote: ""
        )
    }
}
