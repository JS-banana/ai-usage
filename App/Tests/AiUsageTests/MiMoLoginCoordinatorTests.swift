import XCTest
@testable import AiUsage

final class MiMoLoginCoordinatorTests: XCTestCase {
    private let suiteName = "MiMoLoginCoordinatorTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "entitlement.mimo.keychainNamespace")
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        EntitlementPreferences.setSelectedSource(.none, for: .provider("mimo"), userDefaults: defaults)
    }

    override func tearDown() {
        for account in EntitlementPreferences.mimoAccounts(userDefaults: defaults) {
            EntitlementPreferences.clearMiMoServiceToken(forAccount: account.id, userDefaults: defaults)
        }
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSuccessfulLoginStoresAccountTokenAndSelectsMiMoSource() async throws {
        let token = MiMoServiceToken(serviceToken: "svc", userId: "user-id", slh: "slh", ph: "ph", acquiredAt: Date())
        let coordinator = MiMoLoginCoordinator(
            authService: StubMiMoAuthenticator(result: .success(token)),
            userDefaults: defaults
        )
        let credentials = MiMoCredentials(username: "user@example.com", passwordMD5: "HASH")

        try await coordinator.login(credentials: credentials)

        let accounts = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].credentials, credentials)
        XCTAssertEqual(EntitlementPreferences.mimoServiceToken(forAccount: accounts[0].id, userDefaults: defaults)?.serviceToken, "svc")
        XCTAssertEqual(EntitlementPreferences.selectedSourceBindingValue(for: .provider("mimo"), userDefaults: defaults), .mimo)
    }

    func testSuccessfulWebSessionLoginStoresAccountTokenAndSelectsMiMoSource() async throws {
        let token = MiMoServiceToken(
            serviceToken: "web-svc",
            userId: "123456",
            slh: "web-slh",
            ph: "web-ph",
            acquiredAt: Date()
        )
        let coordinator = MiMoLoginCoordinator(
            authService: StubMiMoAuthenticator(result: .failure(MiMoSSOAuthService.AuthError.invalidCredentials)),
            userDefaults: defaults
        )

        try await coordinator.storeWebSession(token: token, displayName: "MiMo 123456")

        let accounts = EntitlementPreferences.mimoAccounts(userDefaults: defaults)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].credentials.username, "123456")
        XCTAssertEqual(accounts[0].credentials.passwordMD5, "")
        XCTAssertEqual(accounts[0].displayName, "MiMo 123456")
        XCTAssertEqual(EntitlementPreferences.mimoServiceToken(forAccount: accounts[0].id, userDefaults: defaults)?.serviceToken, "web-svc")
        XCTAssertEqual(EntitlementPreferences.selectedSourceBindingValue(for: .provider("mimo"), userDefaults: defaults), .mimo)
    }

    func testFailedLoginDoesNotPersistAccountOrSelectMiMoSource() async {
        let coordinator = MiMoLoginCoordinator(
            authService: StubMiMoAuthenticator(result: .failure(MiMoSSOAuthService.AuthError.invalidCredentials)),
            userDefaults: defaults
        )

        do {
            try await coordinator.login(credentials: MiMoCredentials(username: "bad", passwordMD5: "BAD"))
            XCTFail("Expected login failure")
        } catch {
            XCTAssertTrue(EntitlementPreferences.mimoAccounts(userDefaults: defaults).isEmpty)
            XCTAssertEqual(EntitlementPreferences.selectedSourceBindingValue(for: .provider("mimo"), userDefaults: defaults), .none)
        }
    }
}

private struct StubMiMoAuthenticator: MiMoAuthenticating {
    let result: Result<MiMoServiceToken, Error>

    func login(credentials: MiMoCredentials) async throws -> MiMoServiceToken {
        try result.get()
    }
}
