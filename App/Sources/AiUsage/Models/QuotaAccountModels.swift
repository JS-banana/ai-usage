import Foundation

enum QuotaAccountStatus: String, Hashable, Sendable {
    case ready
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
        userDefaults: UserDefaults = .standard
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
                accounts: mimoAccounts.map { account in
                    let accountTargetKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: account.id)
                    return QuotaAccountRowSnapshot(
                        id: accountTargetKey,
                        title: title(for: account),
                        subtitle: subtitle(for: account),
                        planName: planName(for: account),
                        status: accountsWithToken.contains(account.id) ? .ready : .loginRequired,
                        summary: entitlementsByTarget[accountTargetKey]
                    )
                }
            )
        ]
    }

    private static func title(for account: MiMoAccount) -> String {
        for value in [
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

    private static func subtitle(for account: MiMoAccount) -> String {
        let username = account.credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.isEmpty == false, isTechnicalMiMoID(username) == false else { return "" }
        return title(for: account).localizedCaseInsensitiveContains(username) ? "" : username
    }

    private static func planName(for account: MiMoAccount) -> String {
        (account.planName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
