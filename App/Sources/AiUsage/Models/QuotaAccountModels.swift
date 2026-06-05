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
    let status: QuotaAccountStatus
    let summary: EntitlementSummarySnapshot?
    let menuBarTarget: QuotaMenuBarTargetPreference
}

struct QuotaVendorGroupSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: EntitlementSummarySnapshot
    let accounts: [QuotaAccountRowSnapshot]
    let menuBarTarget: QuotaMenuBarTargetPreference
}

enum QuotaAccountReadModel {
    static func makeGroups(
        entitlementsByTarget: [String: EntitlementSummarySnapshot],
        userDefaults: UserDefaults = .standard
    ) -> [QuotaVendorGroupSnapshot] {
        let mimoAccounts = EntitlementPreferences.mimoAccounts(userDefaults: userDefaults)
        guard mimoAccounts.isEmpty == false || entitlementsByTarget["mimo"] != nil else {
            return []
        }
        return [
            QuotaVendorGroupSnapshot(
                id: "mimo",
                title: "MiMo",
                summary: entitlementsByTarget["mimo"] ?? missingSummary(providerID: "mimo", title: "MiMo", sourceKind: .mimo),
                accounts: mimoAccounts.map { account in
                    let accountTargetKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: account.id)
                    return QuotaAccountRowSnapshot(
                        id: accountTargetKey,
                        title: account.displayName,
                        subtitle: account.credentials.username,
                        status: EntitlementPreferences.mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) == nil ? .loginRequired : .ready,
                        summary: entitlementsByTarget[accountTargetKey],
                        menuBarTarget: .target(accountTargetKey)
                    )
                },
                menuBarTarget: .target("mimo")
            )
        ]
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
