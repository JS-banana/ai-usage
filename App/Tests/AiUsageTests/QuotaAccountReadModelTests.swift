import XCTest
@testable import AiUsage

final class QuotaAccountReadModelTests: XCTestCase {
    func testMiMoAccountsBecomeSingleVendorGroupWithAggregateSummary() {
        let defaults = makeDefaults("QuotaAccountReadModelTests")
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: firstID,
                credentials: MiMoCredentials(username: "first@example.com", passwordMD5: ""),
                displayName: "MiMo Main"
            ),
            MiMoAccount(
                id: secondID,
                credentials: MiMoCredentials(username: "second@example.com", passwordMD5: ""),
                displayName: "MiMo Backup"
            )
        ], userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "token", userId: "1", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: firstID,
            userDefaults: defaults
        )
        let summary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "MiMo",
            message: "",
            updatedAt: Date(),
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(
                id: "mimo-primary",
                title: "套餐总额度",
                detailText: "10M / 20M tokens",
                primaryText: "50% used",
                secondaryText: "expires 2026/7/1",
                footnoteText: "",
                progress: 0.5
            ),
            secondaryWindow: .hidden(id: "mimo-secondary"),
            menuBarProgress: 0.5
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: ["mimo": summary],
            userDefaults: defaults
        )

        XCTAssertEqual(groups.map(\.id), ["mimo"])
        let group = try! XCTUnwrap(groups.first)
        XCTAssertEqual(group.title, "MiMo")
        XCTAssertEqual(group.summary, summary)
        XCTAssertEqual(group.accounts.map(\.title), ["MiMo Main", "MiMo Backup"])
        XCTAssertEqual(group.accounts.map(\.subtitle), ["first@example.com", "second@example.com"])
        XCTAssertEqual(group.accounts.map(\.status), [.ready, .loginRequired])
        XCTAssertNil(group.accounts.first?.summary)
    }

    func testMiMoAccountRowsAttachPerAccountSummaries() {
        let defaults = makeDefaults("QuotaAccountReadModelAccountSummaryTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "first@example.com", passwordMD5: ""),
                displayName: "MiMo Main"
            )
        ], userDefaults: defaults)
        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)
        let accountSummary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "MiMo Main",
            message: "",
            updatedAt: Date(),
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(id: "mimo-primary", title: "套餐总额度", primaryText: "20% used", secondaryText: "", footnoteText: "", progress: 0.2),
            secondaryWindow: .hidden(id: "mimo-secondary"),
            menuBarProgress: 0.2
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [accountKey: accountSummary],
            userDefaults: defaults
        )

        XCTAssertEqual(groups.first?.accounts.first?.summary, accountSummary)
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(name, forKey: "entitlement.mimo.keychainNamespace")
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        return defaults
    }
}
