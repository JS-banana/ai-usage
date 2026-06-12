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
        XCTAssertEqual(group.accounts.map(\.status), [.failed, .loginRequired])
        XCTAssertNil(group.accounts.first?.summary)
    }

    func testMiMoGroupsStayEmptyWhenNoAccountsExistEvenIfVendorSummaryExists() {
        let defaults = makeDefaults("QuotaAccountReadModelNoAccountsTests")
        let providerSummary = EntitlementSummarySnapshot.placeholder(
            targetID: .provider("mimo"),
            title: "MiMo",
            message: "",
            status: .ready,
            sourceKind: .mimo,
            primaryTitle: "套餐总额度",
            secondaryTitle: "",
            primaryText: "20% used",
            secondaryText: "",
            footnote: ""
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: ["mimo": providerSummary],
            userDefaults: defaults
        )

        XCTAssertTrue(groups.isEmpty)
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

    func testSingleMiMoAccountHidesVendorAggregateSummary() throws {
        let defaults = makeDefaults("QuotaAccountReadModelSingleAccountSummaryTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "897298966", passwordMD5: ""),
                displayName: "MiMo 897298966",
                email: "ooo***y@163.com",
                planName: "Standard"
            )
        ], userDefaults: defaults)
        let providerSummary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "MiMo",
            message: "",
            updatedAt: Date(),
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(
                id: "mimo-provider-primary",
                title: "套餐总额度",
                primaryText: "29% used",
                secondaryText: "",
                footnoteText: "",
                progress: 0.29
            ),
            secondaryWindow: .hidden(id: "mimo-provider-secondary"),
            menuBarProgress: 0.29
        )
        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)
        let accountSummary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "ooo***y@163.com",
            message: "",
            updatedAt: Date(),
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(
                id: "mimo-account-primary",
                title: "账号额度",
                detailText: "2.05B / 14.29B tokens",
                primaryText: "14% used",
                secondaryText: "expires 2026/6/27",
                footnoteText: "",
                progress: 0.143
            ),
            secondaryWindow: .hidden(id: "mimo-account-secondary"),
            menuBarProgress: 0.143
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [
                "mimo": providerSummary,
                accountKey: accountSummary
            ],
            userDefaults: defaults
        )

        let group = try XCTUnwrap(groups.first)
        XCTAssertNil(group.summary)
        let account = try XCTUnwrap(group.accounts.first)
        XCTAssertEqual(account.title, "ooo***y@163.com")
        XCTAssertEqual(account.planName, "Standard")
        XCTAssertEqual(account.summary, accountSummary)
    }

    func testMultipleMiMoAccountsShowVendorAggregateSummary() throws {
        let defaults = makeDefaults("QuotaAccountReadModelMultiAccountSummaryTests")
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: firstID,
                credentials: MiMoCredentials(username: "first", passwordMD5: ""),
                displayName: "First",
                email: "first@example.com",
                planName: "Standard"
            ),
            MiMoAccount(
                id: secondID,
                credentials: MiMoCredentials(username: "second", passwordMD5: ""),
                displayName: "Second",
                email: "second@example.com",
                planName: "Standard"
            )
        ], userDefaults: defaults)
        let providerSummary = EntitlementSummarySnapshot.placeholder(
            targetID: .provider("mimo"),
            title: "MiMo",
            message: "",
            status: .ready,
            sourceKind: .mimo,
            primaryTitle: "套餐总额度",
            secondaryTitle: "",
            primaryText: "20% used",
            secondaryText: "",
            footnote: ""
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: ["mimo": providerSummary],
            userDefaults: defaults
        )

        XCTAssertEqual(groups.first?.summary, providerSummary)
        XCTAssertEqual(groups.first?.accounts.count, 2)
    }

    func testMiMoAccountRowHidesTechnicalUserIDWhenNoProfileExists() {
        let defaults = makeDefaults("QuotaAccountReadModelDuplicateSubtitleTests")
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                credentials: MiMoCredentials(username: "897298966", passwordMD5: ""),
                displayName: "MiMo 897298966"
            )
        ], userDefaults: defaults)

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        XCTAssertEqual(groups.first?.accounts.first?.title, "账号 1")
        XCTAssertEqual(groups.first?.accounts.first?.subtitle, "")
    }

    func testMiMoAccountRowsFallbackToOrderedNeutralLabelWhenNoReadableIdentityExists() throws {
        let defaults = makeDefaults("QuotaAccountReadModelNeutralFallbackTests")
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let now = Date(timeIntervalSince1970: 1_718_000_000)
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: firstID,
                credentials: MiMoCredentials(username: "123456789", passwordMD5: ""),
                displayName: "MiMo 123456789"
            ),
            MiMoAccount(
                id: secondID,
                credentials: MiMoCredentials(username: "987654321", passwordMD5: ""),
                displayName: "MiMo 987654321"
            )
        ], userDefaults: defaults)

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults,
            now: now
        )

        let accounts = try XCTUnwrap(groups.first?.accounts)
        XCTAssertEqual(accounts.map(\.title), ["账号 1", "账号 2"])
        XCTAssertEqual(accounts.map(\.subtitle), ["", ""])
    }

    func testMiMoAccountRowsUseReadableSummaryTitleBeforeFallingBackToNeutralLabel() throws {
        let defaults = makeDefaults("QuotaAccountReadModelReadableSummaryTitleTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "123456789", passwordMD5: ""),
                displayName: "MiMo 123456789"
            )
        ], userDefaults: defaults)

        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)
        let summary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "ooo***k@gmail.com",
            message: "",
            updatedAt: Date(),
            status: .stale,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(
                id: "mimo-account-primary",
                title: "账号额度",
                primaryText: "14% used",
                secondaryText: "",
                footnoteText: "",
                progress: 0.14
            ),
            secondaryWindow: .hidden(id: "mimo-account-secondary"),
            menuBarProgress: 0.14
        )

        let account = try XCTUnwrap(QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [accountKey: summary],
            userDefaults: defaults
        ).first?.accounts.first)

        XCTAssertEqual(account.title, "ooo***k@gmail.com")
    }

    func testMiMoAccountRowsUseNumericPhoneAsReadableTitle() throws {
        let defaults = makeDefaults("QuotaAccountReadModelNumericPhoneTitleTests")
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                credentials: MiMoCredentials(username: "897298966", passwordMD5: ""),
                displayName: "MiMo 897298966",
                phone: "13800138000"
            )
        ], userDefaults: defaults)

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        let account = try XCTUnwrap(groups.first?.accounts.first)
        XCTAssertEqual(account.title, "13800138000")
        XCTAssertEqual(account.subtitle, "")
    }

    func testMiMoAccountRowsExposeFooterStatusTextForReadyStaleAndLoginRequired() throws {
        let defaults = makeDefaults("QuotaAccountReadModelFooterStatusTests")
        let readyID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let staleID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let loginRequiredID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let now = Date(timeIntervalSince1970: 1_718_000_000)
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: readyID,
                credentials: MiMoCredentials(username: "ready@example.com", passwordMD5: ""),
                displayName: "Ready Account"
            ),
            MiMoAccount(
                id: staleID,
                credentials: MiMoCredentials(username: "stale@example.com", passwordMD5: ""),
                displayName: "Stale Account"
            ),
            MiMoAccount(
                id: loginRequiredID,
                credentials: MiMoCredentials(username: "login@example.com", passwordMD5: ""),
                displayName: "Login Required Account"
            )
        ], userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "ready-token", userId: "1", slh: "s", ph: "p", acquiredAt: now),
            forAccount: readyID,
            userDefaults: defaults
        )
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "stale-token", userId: "2", slh: "s", ph: "p", acquiredAt: now),
            forAccount: staleID,
            userDefaults: defaults
        )

        let readySummary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "Ready Account",
            message: "",
            updatedAt: now.addingTimeInterval(-120),
            status: .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(id: "ready-primary", title: "账号额度", primaryText: "10% used", secondaryText: "", footnoteText: "", progress: 0.1),
            secondaryWindow: .hidden(id: "ready-secondary"),
            menuBarProgress: 0.1
        )
        let staleSummary = EntitlementSummarySnapshot(
            targetID: .provider("mimo"),
            title: "Stale Account",
            message: "",
            updatedAt: now.addingTimeInterval(-300),
            status: .stale,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(id: "stale-primary", title: "账号额度", primaryText: "40% used", secondaryText: "", footnoteText: "", progress: 0.4),
            secondaryWindow: .hidden(id: "stale-secondary"),
            menuBarProgress: 0.4
        )

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [
                QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: readyID): readySummary,
                QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: staleID): staleSummary
            ],
            userDefaults: defaults,
            now: now
        )

        let accounts = try XCTUnwrap(groups.first?.accounts)
        XCTAssertEqual(accounts.map(\.footerStatusText), [
            "updated 2 min. ago",
            "last success 5 min. ago",
            "login required"
        ])
    }

    func testMiMoAccountRowsMapFailedSummaryToFailedWhenTokenExists() throws {
        let defaults = makeDefaults("QuotaAccountReadModelFailedWithTokenTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "failed@example.com", passwordMD5: ""),
                displayName: "Failed Account"
            )
        ], userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "token", userId: "1", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: accountID,
            userDefaults: defaults
        )
        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)
        let summary = EntitlementSummarySnapshot.placeholder(
            targetID: .provider("mimo"),
            title: "Failed Account",
            message: "",
            status: .failed,
            sourceKind: .mimo,
            primaryTitle: "账号额度",
            secondaryTitle: "",
            primaryText: "",
            secondaryText: "",
            footnote: ""
        )

        let account = try XCTUnwrap(QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [accountKey: summary],
            userDefaults: defaults
        ).first?.accounts.first)

        XCTAssertEqual(account.status, .failed)
        XCTAssertEqual(account.footerStatusText, "refresh failed")
    }

    func testMiMoAccountRowsMapFailedSummaryToLoginRequiredWithoutToken() throws {
        let defaults = makeDefaults("QuotaAccountReadModelFailedWithoutTokenTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "failed@example.com", passwordMD5: ""),
                displayName: "Failed Account"
            )
        ], userDefaults: defaults)
        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: accountID)
        let summary = EntitlementSummarySnapshot.placeholder(
            targetID: .provider("mimo"),
            title: "Failed Account",
            message: "",
            status: .failed,
            sourceKind: .mimo,
            primaryTitle: "账号额度",
            secondaryTitle: "",
            primaryText: "",
            secondaryText: "",
            footnote: ""
        )

        let account = try XCTUnwrap(QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [accountKey: summary],
            userDefaults: defaults
        ).first?.accounts.first)

        XCTAssertEqual(account.status, .loginRequired)
        XCTAssertEqual(account.footerStatusText, "login required")
    }

    func testMiMoAccountRowsMapNonReadySummaryStatusesBasedOnTokenPresence() throws {
        let statuses: [EntitlementSummaryStatus] = [.unconfigured, .configuredNonlive, .unavailable]

        for status in statuses {
            let withTokenDefaults = makeDefaults("QuotaAccountReadModel\(status.rawValue)WithTokenTests")
            let withTokenAccountID = UUID()
            EntitlementPreferences.setMiMoAccounts([
                MiMoAccount(
                    id: withTokenAccountID,
                    credentials: MiMoCredentials(username: "\(status.rawValue)-with-token@example.com", passwordMD5: ""),
                    displayName: "With Token"
                )
            ], userDefaults: withTokenDefaults)
            EntitlementPreferences.setMiMoServiceToken(
                MiMoServiceToken(serviceToken: "token", userId: "1", slh: "s", ph: "p", acquiredAt: Date()),
                forAccount: withTokenAccountID,
                userDefaults: withTokenDefaults
            )
            let withTokenKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: withTokenAccountID)
            let withTokenSummary = EntitlementSummarySnapshot.placeholder(
                targetID: .provider("mimo"),
                title: "With Token",
                message: "",
                status: status,
                sourceKind: .mimo,
                primaryTitle: "账号额度",
                secondaryTitle: "",
                primaryText: "",
                secondaryText: "",
                footnote: ""
            )
            let withTokenAccount = try XCTUnwrap(QuotaAccountReadModel.makeGroups(
                entitlementsByTarget: [withTokenKey: withTokenSummary],
                userDefaults: withTokenDefaults
            ).first?.accounts.first)
            XCTAssertEqual(withTokenAccount.status, .failed, "Expected .failed for \(status.rawValue) with token")

            let withoutTokenDefaults = makeDefaults("QuotaAccountReadModel\(status.rawValue)WithoutTokenTests")
            let withoutTokenAccountID = UUID()
            EntitlementPreferences.setMiMoAccounts([
                MiMoAccount(
                    id: withoutTokenAccountID,
                    credentials: MiMoCredentials(username: "\(status.rawValue)-without-token@example.com", passwordMD5: ""),
                    displayName: "Without Token"
                )
            ], userDefaults: withoutTokenDefaults)
            let withoutTokenKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: withoutTokenAccountID)
            let withoutTokenSummary = EntitlementSummarySnapshot.placeholder(
                targetID: .provider("mimo"),
                title: "Without Token",
                message: "",
                status: status,
                sourceKind: .mimo,
                primaryTitle: "账号额度",
                secondaryTitle: "",
                primaryText: "",
                secondaryText: "",
                footnote: ""
            )
            let withoutTokenAccount = try XCTUnwrap(QuotaAccountReadModel.makeGroups(
                entitlementsByTarget: [withoutTokenKey: withoutTokenSummary],
                userDefaults: withoutTokenDefaults
            ).first?.accounts.first)
            XCTAssertEqual(withoutTokenAccount.status, .loginRequired, "Expected .loginRequired for \(status.rawValue) without token")
        }
    }

    func testMiMoAccountRowsUseNonSecretMirrorsForDisplayState() throws {
        let defaults = makeDefaults("QuotaAccountReadModelMirrorStateTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let mirrorJSON = """
        [{"id":"\(accountID.uuidString)","username":"mirrored@example.com","displayName":"MiMo Mirror"}]
        """
        defaults.set(Data(mirrorJSON.utf8), forKey: "entitlement.mimo.accounts.mirror")
        defaults.set([accountID.uuidString], forKey: "entitlement.mimo.tokenPresence.mirror")

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        let account = try XCTUnwrap(groups.first?.accounts.first)
        XCTAssertEqual(account.title, "MiMo Mirror")
        XCTAssertEqual(account.subtitle, "mirrored@example.com")
        XCTAssertEqual(account.status, .failed)
    }

    func testMiMoAccountRowsPreferProfileEmailAndPlanNameOverUserID() throws {
        let defaults = makeDefaults("QuotaAccountReadModelProfileMirrorTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let mirrorJSON = """
        [{
            "id":"\(accountID.uuidString)",
            "username":"897298966",
            "displayName":"MiMo 897298966",
            "email":"ooo***y@163.com",
            "phone":"+86 150****8613",
            "planName":"Standard"
        }]
        """
        defaults.set(Data(mirrorJSON.utf8), forKey: "entitlement.mimo.accounts.mirror")
        defaults.set([accountID.uuidString], forKey: "entitlement.mimo.tokenPresence.mirror")

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        let account = try XCTUnwrap(groups.first?.accounts.first)
        XCTAssertEqual(account.title, "ooo***y@163.com")
        XCTAssertEqual(account.subtitle, "")
        XCTAssertEqual(account.planName, "Standard")
        XCTAssertFalse(account.title.contains("897298966"))
        XCTAssertFalse(account.subtitle.contains("897298966"))
        XCTAssertFalse(account.planName.contains("897298966"))
    }

    func testMiMoAccountRowsPreferDisplayMirrorOverKeychainAccounts() throws {
        let defaults = makeDefaults("QuotaAccountReadModelMirrorPreferredTests")
        let keychainAccount = MiMoAccount(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            credentials: MiMoCredentials(username: "keychain@example.com", passwordMD5: ""),
            displayName: "Keychain Account"
        )
        let mirrorAccountID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let mirrorJSON = """
        [{"id":"\(mirrorAccountID.uuidString)","username":"mirror@example.com","displayName":"Mirror Account"}]
        """
        EntitlementPreferences.setMiMoAccounts([keychainAccount], userDefaults: defaults)
        defaults.set(Data(mirrorJSON.utf8), forKey: "entitlement.mimo.accounts.mirror")

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        XCTAssertEqual(groups.first?.accounts.map(\.title), ["Mirror Account"])
    }

    func testMiMoAccountRowsFallbackToKeychainAccountsWhenDisplayMirrorMissing() throws {
        let defaults = makeDefaults("QuotaAccountReadModelKeychainFallbackTests")
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        EntitlementPreferences.setMiMoAccounts([
            MiMoAccount(
                id: accountID,
                credentials: MiMoCredentials(username: "legacy@example.com", passwordMD5: ""),
                displayName: "Legacy MiMo"
            )
        ], userDefaults: defaults)
        defaults.removeObject(forKey: "entitlement.mimo.accounts.mirror")
        defaults.removeObject(forKey: "entitlement.mimo.tokenPresence.mirror")
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "token", userId: "1", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: accountID,
            userDefaults: defaults
        )
        defaults.removeObject(forKey: "entitlement.mimo.tokenPresence.mirror")

        let groups = QuotaAccountReadModel.makeGroups(
            entitlementsByTarget: [:],
            userDefaults: defaults
        )

        let account = try XCTUnwrap(groups.first?.accounts.first)
        XCTAssertEqual(account.title, "Legacy MiMo")
        XCTAssertEqual(account.subtitle, "legacy@example.com")
        XCTAssertEqual(account.status, .failed)
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(name, forKey: "entitlement.mimo.keychainNamespace")
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        return defaults
    }
}
