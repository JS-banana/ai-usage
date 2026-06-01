import Foundation

protocol MiMoAuthenticating: Sendable {
    func login(credentials: MiMoCredentials) async throws -> MiMoServiceToken
}

extension MiMoSSOAuthService: MiMoAuthenticating {}

struct MiMoLoginCoordinator {
    private let authService: (any MiMoAuthenticating)?
    private let userDefaults: UserDefaults

    init(authService: any MiMoAuthenticating, userDefaults: UserDefaults = .standard) {
        self.authService = authService
        self.userDefaults = userDefaults
    }

    init(userDefaults: UserDefaults = .standard) {
        self.authService = nil
        self.userDefaults = userDefaults
    }

    func login(credentials: MiMoCredentials) async throws {
        guard let authService else {
            throw MiMoSSOAuthService.AuthError.riskControl
        }
        let token = try await authService.login(credentials: credentials)
        let account = EntitlementPreferences.addMiMoAccount(
            MiMoAccount(credentials: credentials),
            userDefaults: userDefaults
        )
        EntitlementPreferences.setMiMoServiceToken(token, forAccount: account.id, userDefaults: userDefaults)
        EntitlementPreferences.setSelectedSource(.mimo, for: .provider("mimo"), userDefaults: userDefaults)
    }

    func storeWebSession(token: MiMoServiceToken, displayName: String? = nil) async throws {
        let account = EntitlementPreferences.addMiMoAccount(
            MiMoAccount(
                credentials: MiMoCredentials(username: token.userId, passwordMD5: ""),
                displayName: displayName ?? "MiMo \(token.userId)"
            ),
            userDefaults: userDefaults
        )
        EntitlementPreferences.setMiMoServiceToken(token, forAccount: account.id, userDefaults: userDefaults)
        EntitlementPreferences.setSelectedSource(.mimo, for: .provider("mimo"), userDefaults: userDefaults)
    }
}
