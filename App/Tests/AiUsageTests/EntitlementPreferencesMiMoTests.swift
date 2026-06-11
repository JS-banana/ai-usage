import XCTest
@testable import AiUsage

final class EntitlementPreferencesMiMoTests: XCTestCase {

    private let suiteName = "EntitlementPreferencesMiMoTests"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "entitlement.mimo.keychainNamespace")
        // Clean Keychain entries
        EntitlementPreferences.clearMiMoCredentials(userDefaults: defaults)
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: accountA, userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: accountB, userDefaults: defaults)
    }

    override func tearDown() {
        EntitlementPreferences.clearMiMoCredentials(userDefaults: defaults)
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: accountA, userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: accountB, userDefaults: defaults)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Credentials (Keychain)

    func testMiMoCredentialsInitiallyNil() {
        let creds = EntitlementPreferences.mimoCredentials(userDefaults: defaults)
        XCTAssertNil(creds)
    }

    func testSetAndReadMiMoCredentials() {
        let creds = MiMoCredentials(username: "testuser", passwordMD5: "ABC123DEF")
        EntitlementPreferences.setMiMoCredentials(creds, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoCredentials(userDefaults: defaults)
        XCTAssertEqual(loaded?.username, "testuser")
        XCTAssertEqual(loaded?.passwordMD5, "ABC123DEF")
    }

    func testSetMiMoCredentialsOverwritesPrevious() {
        EntitlementPreferences.setMiMoCredentials(
            MiMoCredentials(username: "old", passwordMD5: "OLD"),
            userDefaults: defaults
        )
        EntitlementPreferences.setMiMoCredentials(
            MiMoCredentials(username: "new", passwordMD5: "NEW"),
            userDefaults: defaults
        )

        let loaded = EntitlementPreferences.mimoCredentials(userDefaults: defaults)
        XCTAssertEqual(loaded?.username, "new")
        XCTAssertEqual(loaded?.passwordMD5, "NEW")
    }

    func testClearMiMoCredentialsRemovesEntry() {
        EntitlementPreferences.setMiMoCredentials(
            MiMoCredentials(username: "user", passwordMD5: "HASH"),
            userDefaults: defaults
        )
        EntitlementPreferences.clearMiMoCredentials(userDefaults: defaults)

        XCTAssertNil(EntitlementPreferences.mimoCredentials(userDefaults: defaults))
    }

    // MARK: - ServiceToken (Keychain, keyed by account ID)

    private let accountA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let accountB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testMiMoServiceTokenInitiallyNil() {
        let token = EntitlementPreferences.mimoServiceToken(forAccount: accountA, userDefaults: defaults)
        XCTAssertNil(token)
    }

    func testSetAndReadMiMoServiceToken() {
        let now = Date()
        let token = MiMoServiceToken(
            serviceToken: "svc_tok",
            userId: "123",
            slh: "slh_val",
            ph: "ph_val",
            acquiredAt: now
        )
        EntitlementPreferences.setMiMoServiceToken(token, forAccount: accountA, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoServiceToken(forAccount: accountA, userDefaults: defaults)
        XCTAssertEqual(loaded?.serviceToken, "svc_tok")
        XCTAssertEqual(loaded?.userId, "123")
        XCTAssertEqual(loaded?.slh, "slh_val")
        XCTAssertEqual(loaded?.ph, "ph_val")
        XCTAssertEqual(EntitlementPreferences.mimoAccountIDsWithStoredToken(userDefaults: defaults), [accountA])
    }

    func testSetMiMoServiceTokenDoesNotPersistSecretInUserDefaults() {
        let token = MiMoServiceToken(
            serviceToken: "svc_tok",
            userId: "123",
            slh: "slh_val",
            ph: "ph_val",
            acquiredAt: Date()
        )

        EntitlementPreferences.setMiMoServiceToken(token, forAccount: accountA, userDefaults: defaults)

        let legacyKeyPrefix = "entitlement.mimo.account.\(accountA.uuidString).token."
        XCTAssertNil(defaults.string(forKey: legacyKeyPrefix + "serviceToken"))
        XCTAssertNil(defaults.string(forKey: legacyKeyPrefix + "slh"))
        XCTAssertNil(defaults.string(forKey: legacyKeyPrefix + "ph"))
        XCTAssertFalse((defaults.stringArray(forKey: "entitlement.mimo.tokenPresence.mirror") ?? []).contains("svc_tok"))
    }

    func testMiMoServiceTokenIsolatedByAccountID() {
        let token = MiMoServiceToken(
            serviceToken: "tok_a",
            userId: "1",
            slh: "s",
            ph: "p",
            acquiredAt: Date()
        )
        EntitlementPreferences.setMiMoServiceToken(token, forAccount: accountA, userDefaults: defaults)

        let otherAccount = EntitlementPreferences.mimoServiceToken(forAccount: accountB, userDefaults: defaults)
        XCTAssertNil(otherAccount, "Token for account B should be nil when only account A has a token")
    }

    func testClearMiMoServiceTokenRemovesEntry() {
        let token = MiMoServiceToken(
            serviceToken: "tok",
            userId: "1",
            slh: "s",
            ph: "p",
            acquiredAt: Date()
        )
        EntitlementPreferences.setMiMoServiceToken(token, forAccount: accountA, userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: accountA, userDefaults: defaults)

        XCTAssertNil(EntitlementPreferences.mimoServiceToken(forAccount: accountA, userDefaults: defaults))
        XCTAssertFalse(EntitlementPreferences.mimoAccountIDsWithStoredToken(userDefaults: defaults).contains(accountA))
    }

    func testSetMiMoServiceTokenOverwritesPrevious() {
        let token1 = MiMoServiceToken(serviceToken: "old", userId: "1", slh: "s", ph: "p", acquiredAt: Date())
        let token2 = MiMoServiceToken(serviceToken: "new", userId: "2", slh: "s2", ph: "p2", acquiredAt: Date())

        EntitlementPreferences.setMiMoServiceToken(token1, forAccount: accountA, userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(token2, forAccount: accountA, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoServiceToken(forAccount: accountA, userDefaults: defaults)
        XCTAssertEqual(loaded?.serviceToken, "new")
        XCTAssertEqual(loaded?.userId, "2")
    }

    func testMiMoConfigurationSeedsSelectedSourceWhenStoredWebSessionExists() {
        let account = MiMoAccount(
            id: accountA,
            credentials: MiMoCredentials(username: "123456", passwordMD5: ""),
            displayName: "MiMo 123456"
        )
        EntitlementPreferences.setMiMoAccounts([account], userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "tok", userId: "123456", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: accountA,
            userDefaults: defaults
        )

        let configuration = EntitlementPreferences.configuration(for: .provider("mimo"), userDefaults: defaults)

        XCTAssertEqual(configuration.selectedSource, .mimo)
        XCTAssertEqual(
            EntitlementPreferences.selectedSourceBindingValue(for: .provider("mimo"), userDefaults: defaults),
            .mimo
        )
    }

    // MARK: - Multi-Account Storage (Keychain)

    func testMimoAccountsInitiallyEmpty() {
        let accounts = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertTrue(accounts.isEmpty)
    }

    func testSetAndReadMimoAccounts() {
        let a1 = MiMoAccount(id: UUID(), credentials: MiMoCredentials(username: "user1", passwordMD5: "H1"), displayName: "First")
        let a2 = MiMoAccount(id: UUID(), credentials: MiMoCredentials(username: "user2", passwordMD5: "H2"), displayName: "Second")
        EntitlementPreferences.setMiMoAccounts([a1, a2], userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, a1.id)
        XCTAssertEqual(loaded[0].credentials.username, "user1")
        XCTAssertEqual(loaded[0].displayName, "First")
        XCTAssertEqual(loaded[1].id, a2.id)
        XCTAssertEqual(loaded[1].credentials.username, "user2")
        XCTAssertEqual(loaded[1].displayName, "Second")
    }

    func testMimoAccountsMirrorDoesNotStorePasswordMD5() throws {
        let account = MiMoAccount(
            id: accountA,
            credentials: MiMoCredentials(username: "user@example.com", passwordMD5: "SECRET_MD5"),
            displayName: "User"
        )

        EntitlementPreferences.setMiMoAccounts([account], userDefaults: defaults)

        let mirrorData = try XCTUnwrap(defaults.data(forKey: "entitlement.mimo.accounts.mirror"))
        let mirrorText = String(data: mirrorData, encoding: .utf8) ?? ""
        XCTAssertFalse(mirrorText.contains("SECRET_MD5"))
        XCTAssertFalse(mirrorText.contains("passwordMD5"))
    }

    func testSetMimoAccountsOverwritesPrevious() {
        let a1 = MiMoAccount(credentials: MiMoCredentials(username: "old", passwordMD5: "O"))
        let a2 = MiMoAccount(credentials: MiMoCredentials(username: "new", passwordMD5: "N"))
        EntitlementPreferences.setMiMoAccounts([a1], userDefaults: defaults)
        EntitlementPreferences.setMiMoAccounts([a2], userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].credentials.username, "new")
    }

    func testAddMimoAccountAppendsToList() {
        let a1 = MiMoAccount(credentials: MiMoCredentials(username: "first", passwordMD5: "F"))
        EntitlementPreferences.setMiMoAccounts([a1], userDefaults: defaults)

        let a2 = MiMoAccount(credentials: MiMoCredentials(username: "second", passwordMD5: "S"))
        EntitlementPreferences.addMiMoAccount(a2, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].credentials.username, "first")
        XCTAssertEqual(loaded[1].credentials.username, "second")
    }

    func testAddMimoAccountUpdatesExistingUsernameWithoutDuplicating() {
        let accountID = UUID()
        let original = MiMoAccount(
            id: accountID,
            credentials: MiMoCredentials(username: "same@example.com", passwordMD5: "OLD"),
            displayName: "Original"
        )
        EntitlementPreferences.setMiMoAccounts([original], userDefaults: defaults)

        let updated = MiMoAccount(
            credentials: MiMoCredentials(username: "same@example.com", passwordMD5: "NEW"),
            displayName: "Updated"
        )
        EntitlementPreferences.addMiMoAccount(updated, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, accountID)
        XCTAssertEqual(loaded[0].credentials.passwordMD5, "NEW")
        XCTAssertEqual(loaded[0].displayName, "Updated")
    }

    func testRemoveMimoAccountRemovesByID() {
        let keepID = UUID()
        let removeID = UUID()
        let a1 = MiMoAccount(id: keepID, credentials: MiMoCredentials(username: "keep", passwordMD5: "K"))
        let a2 = MiMoAccount(id: removeID, credentials: MiMoCredentials(username: "remove", passwordMD5: "R"))
        EntitlementPreferences.setMiMoAccounts([a1, a2], userDefaults: defaults)

        EntitlementPreferences.removeMiMoAccount(id: removeID, userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, keepID)
    }

    func testRemoveMimoAccountAlsoClearsItsServiceToken() {
        let account = MiMoAccount(id: accountA, credentials: MiMoCredentials(username: "remove", passwordMD5: "R"))
        EntitlementPreferences.setMiMoAccounts([account], userDefaults: defaults)
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "tok", userId: "1", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: accountA,
            userDefaults: defaults
        )

        EntitlementPreferences.removeMiMoAccount(id: accountA, userDefaults: defaults)

        XCTAssertNil(EntitlementPreferences.mimoServiceToken(forAccount: accountA, userDefaults: defaults))
    }

    func testClearMimoAccountsEmptiesList() {
        let a1 = MiMoAccount(credentials: MiMoCredentials(username: "user", passwordMD5: "H"))
        EntitlementPreferences.setMiMoAccounts([a1], userDefaults: defaults)

        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)

        let loaded = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertTrue(loaded.isEmpty)
    }
}
