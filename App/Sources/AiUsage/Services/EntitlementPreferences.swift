import Foundation
import LocalAuthentication
import ProviderKit
import Security

enum EntitlementPreferences {
    private static let prefix = "entitlement.target."
    private static let legacyOverviewMigrationKey = "entitlement.target.overview.legacyMigrated"
    private static let menuBarTargetPreferenceKey = "entitlement.menuBar.target"

    static func menuBarTargetPreference(userDefaults: UserDefaults = .standard) -> QuotaMenuBarTargetPreference {
        QuotaMenuBarTargetPreference(storageValue: userDefaults.string(forKey: menuBarTargetPreferenceKey))
    }

    static func setMenuBarTargetPreference(
        _ preference: QuotaMenuBarTargetPreference,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(preference.storageValue, forKey: menuBarTargetPreferenceKey)
    }

    static func descriptorTargets(providerPreferences: [ProviderPreferenceSnapshot]) -> [EntitlementTargetDescriptor] {
        [EntitlementTargetDescriptor(targetID: .overview, name: "总览", supportsOfficial: false)] + providerPreferences.map {
            EntitlementTargetDescriptor(
                targetID: .provider($0.id),
                name: $0.name,
                supportsOfficial: supportsOfficialSource(for: .provider($0.id))
            )
        }
    }

    static func descriptorTargets(providerDescriptors: [ProviderDescriptor]) -> [EntitlementTargetDescriptor] {
        [EntitlementTargetDescriptor(targetID: .overview, name: "总览", supportsOfficial: false)] + providerDescriptors
            .filter { $0.capabilities.contains(.accountQuotaSnapshots) }
            .map {
                EntitlementTargetDescriptor(
                    targetID: .provider($0.id),
                    name: $0.displayName,
                    supportsOfficial: supportsOfficialSource(for: .provider($0.id))
                )
            }
    }

    static func configuration(
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) -> EntitlementTargetConfiguration {
        ensureLegacyOverviewMigration(userDefaults: userDefaults)
        let keyPrefix = prefix + targetID.storageKey + "."
        let selectedSourceKey = keyPrefix + "selectedSource"
        seedMiMoSourceIfStoredSessionExists(for: targetID, selectedSourceKey: selectedSourceKey, userDefaults: userDefaults)
        let selectedSource = EntitlementSourceSelection(rawValue: userDefaults.string(forKey: selectedSourceKey) ?? "none") ?? .none
        let endpointRaw = (userDefaults.string(forKey: keyPrefix + "bridge.endpointURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (userDefaults.string(forKey: keyPrefix + "bridge.apiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bridgeConfiguration: BridgeEntitlementConfiguration?
        if let endpointURL = normalizedURL(from: endpointRaw), apiKey.isEmpty == false {
            bridgeConfiguration = BridgeEntitlementConfiguration(endpointURL: endpointURL, apiKey: apiKey)
        } else {
            bridgeConfiguration = nil
        }
        return EntitlementTargetConfiguration(
            targetID: targetID,
            selectedSource: selectedSource,
            bridgeConfiguration: bridgeConfiguration
        )
    }

    static func selectedSourceBindingValue(
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) -> EntitlementSourceSelection {
        configuration(for: targetID, userDefaults: userDefaults).selectedSource
    }

    static func setSelectedSource(
        _ selection: EntitlementSourceSelection,
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(selection.rawValue, forKey: prefix + targetID.storageKey + ".selectedSource")
    }

    static func bridgeEndpointRaw(
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) -> String {
        userDefaults.string(forKey: prefix + targetID.storageKey + ".bridge.endpointURL") ?? ""
    }

    static func setBridgeEndpointRaw(
        _ value: String,
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(value, forKey: prefix + targetID.storageKey + ".bridge.endpointURL")
    }

    static func bridgeAPIKey(
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) -> String {
        userDefaults.string(forKey: prefix + targetID.storageKey + ".bridge.apiKey") ?? ""
    }

    static func setBridgeAPIKey(
        _ value: String,
        for targetID: EntitlementTargetID,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(value, forKey: prefix + targetID.storageKey + ".bridge.apiKey")
    }

    static func supportsOfficialSource(for targetID: EntitlementTargetID) -> Bool {
        switch targetID {
        case .overview:
            return false
        case .provider(let providerID):
            return providerID == "codex" || providerID == "claude-code"
        }
    }

    private static func ensureLegacyOverviewMigration(userDefaults: UserDefaults) {
        guard userDefaults.bool(forKey: legacyOverviewMigrationKey) == false else { return }
        let targetID = EntitlementTargetID.overview
        let keyPrefix = prefix + targetID.storageKey + "."
        let existingSource = userDefaults.string(forKey: keyPrefix + "selectedSource")
        let existingURL = userDefaults.string(forKey: keyPrefix + "bridge.endpointURL")
        let existingAPIKey = userDefaults.string(forKey: keyPrefix + "bridge.apiKey")
        guard existingSource == nil, (existingURL ?? "").isEmpty, (existingAPIKey ?? "").isEmpty else {
            userDefaults.set(true, forKey: legacyOverviewMigrationKey)
            return
        }

        guard let legacy = LaifuyouQuotaConfiguration.legacyCurrent(userDefaults: userDefaults) else {
            userDefaults.set(true, forKey: legacyOverviewMigrationKey)
            return
        }

        userDefaults.set(EntitlementSourceSelection.thirdParty.rawValue, forKey: keyPrefix + "selectedSource")
        userDefaults.set(legacy.endpointURL.absoluteString, forKey: keyPrefix + "bridge.endpointURL")
        userDefaults.set(legacy.apiKey, forKey: keyPrefix + "bridge.apiKey")
        userDefaults.set(true, forKey: legacyOverviewMigrationKey)
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        guard rawValue.isEmpty == false else { return nil }
        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        return URL(string: "https://\(rawValue)")
    }

    private static func seedMiMoSourceIfStoredSessionExists(
        for targetID: EntitlementTargetID,
        selectedSourceKey: String,
        userDefaults: UserDefaults
    ) {
        guard userDefaults.object(forKey: selectedSourceKey) == nil else { return }
        guard case .provider(let providerID) = targetID, providerID == "mimo" else { return }
        guard hasStoredMiMoServiceToken(userDefaults: userDefaults) else { return }
        userDefaults.set(EntitlementSourceSelection.mimo.rawValue, forKey: selectedSourceKey)
    }

    private static func hasStoredMiMoServiceToken(userDefaults: UserDefaults) -> Bool {
        mimoAccounts(userDefaults: userDefaults).contains { account in
            mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) != nil
        }
    }

    // MARK: - MiMo Credentials (Keychain)

    private static let mimoCredentialsService = "ai-usage.mimo.credentials"
    private static let mimoKeychainNamespaceKey = "entitlement.mimo.keychainNamespace"

    static func mimoCredentials(userDefaults: UserDefaults = .standard) -> MiMoCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoCredentialsService, userDefaults: userDefaults),
            kSecAttrAccount as String: "xiaomi",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = copyKeychainItem(nonInteractiveKeychainQuery(query), item: &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = json["username"],
              let passwordMD5 = json["passwordMD5"] else { return nil }
        return MiMoCredentials(username: username, passwordMD5: passwordMD5)
    }

    static func setMiMoCredentials(_ creds: MiMoCredentials, userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "username": creds.username,
            "passwordMD5": creds.passwordMD5
        ]) else { return }
        deleteMiMoKeychain(userDefaults: userDefaults)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoCredentialsService, userDefaults: userDefaults),
            kSecAttrAccount as String: "xiaomi",
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func clearMiMoCredentials(userDefaults: UserDefaults = .standard) {
        deleteMiMoKeychain(userDefaults: userDefaults)
    }

    private static func deleteMiMoKeychain(userDefaults: UserDefaults) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoCredentialsService, userDefaults: userDefaults),
            kSecAttrAccount as String: "xiaomi"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - MiMo Multi-Account (Keychain)

    private static let mimoAccountsService = "ai-usage.mimo.accounts"
    private static let mimoAccountsAccount = "accounts"
    private static let mimoAccountsMirrorKey = "entitlement.mimo.accounts.mirror"

    static func mimoAccounts(userDefaults: UserDefaults = .standard) -> [MiMoAccount] {
        if let data = readMiMoAccountsKeychain(userDefaults: userDefaults),
           let accounts = try? JSONDecoder().decode([MiMoAccount].self, from: data) {
            setMiMoAccountsMirror(accounts, userDefaults: userDefaults)
            return accounts
        }
        if let accounts = readMiMoAccountsMirror(userDefaults: userDefaults) {
            return accounts
        }
        // Migration: if old single-credential exists but accounts does not, migrate
        if let legacy = mimoCredentials(userDefaults: userDefaults) {
            let migrated = MiMoAccount(credentials: legacy)
            setMiMoAccounts([migrated], userDefaults: userDefaults)
            return [migrated]
        }
        return []
    }

    static func mimoAccountDisplayMirror(userDefaults: UserDefaults = .standard) -> [MiMoAccount] {
        readMiMoAccountsMirror(userDefaults: userDefaults) ?? mimoAccounts(userDefaults: userDefaults)
    }

    static func setMiMoAccounts(_ accounts: [MiMoAccount], userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        setMiMoAccountsMirror(accounts, userDefaults: userDefaults)
        deleteMiMoAccountsKeychain(userDefaults: userDefaults)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoAccountsService, userDefaults: userDefaults),
            kSecAttrAccount as String: mimoAccountsAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readMiMoAccountsMirror(userDefaults: UserDefaults) -> [MiMoAccount]? {
        guard let data = userDefaults.data(forKey: mimoAccountsMirrorKey),
              let mirrors = try? JSONDecoder().decode([MiMoAccountMirror].self, from: data) else {
            return nil
        }
        return mirrors.map { mirror in
            MiMoAccount(
                id: mirror.id,
                credentials: MiMoCredentials(username: mirror.username, passwordMD5: ""),
                displayName: mirror.displayName,
                email: mirror.email,
                phone: mirror.phone,
                platformEmail: mirror.platformEmail,
                planName: mirror.planName
            )
        }
    }

    private static func setMiMoAccountsMirror(_ accounts: [MiMoAccount], userDefaults: UserDefaults) {
        let mirrors = accounts.map { account in
            MiMoAccountMirror(
                id: account.id,
                username: account.credentials.username,
                displayName: account.displayName,
                email: account.email,
                phone: account.phone,
                platformEmail: account.platformEmail,
                planName: account.planName
            )
        }
        guard let data = try? JSONEncoder().encode(mirrors) else { return }
        userDefaults.set(data, forKey: mimoAccountsMirrorKey)
    }

    @discardableResult
    static func addMiMoAccount(_ account: MiMoAccount, userDefaults: UserDefaults = .standard) -> MiMoAccount {
        var existing = mimoAccounts(userDefaults: userDefaults)
        let savedAccount: MiMoAccount
        if let index = existing.firstIndex(where: { $0.credentials.username == account.credentials.username }) {
            savedAccount = MiMoAccount(
                id: existing[index].id,
                credentials: account.credentials,
                displayName: account.displayName,
                email: account.email,
                phone: account.phone,
                platformEmail: account.platformEmail,
                planName: account.planName
            )
            existing[index] = savedAccount
        } else {
            savedAccount = account
            existing.append(account)
        }
        setMiMoAccounts(existing, userDefaults: userDefaults)
        return savedAccount
    }

    static func updateMiMoAccountDisplayMetadata(
        id: UUID,
        profile: MiMoAccountProfile?,
        planName: String?,
        userDefaults: UserDefaults = .standard
    ) {
        var existing = mimoAccounts(userDefaults: userDefaults)
        guard let index = existing.firstIndex(where: { $0.id == id }) else { return }
        let account = existing[index]
        existing[index] = MiMoAccount(
            id: account.id,
            credentials: account.credentials,
            displayName: profile?.preferredDisplayName ?? account.displayName,
            email: profile?.email ?? account.email,
            phone: profile?.phone ?? account.phone,
            platformEmail: profile?.platformEmail ?? account.platformEmail,
            planName: planName ?? account.planName
        )
        setMiMoAccounts(existing, userDefaults: userDefaults)
    }

    static func removeMiMoAccount(id: UUID, userDefaults: UserDefaults = .standard) {
        var existing = mimoAccounts(userDefaults: userDefaults)
        existing.removeAll { $0.id == id }
        setMiMoAccounts(existing, userDefaults: userDefaults)
        clearMiMoServiceToken(forAccount: id, userDefaults: userDefaults)
    }

    static func clearMiMoAccounts(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: mimoAccountsMirrorKey)
        deleteMiMoAccountsKeychain(userDefaults: userDefaults)
    }

    private static func readMiMoAccountsKeychain(userDefaults: UserDefaults) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoAccountsService, userDefaults: userDefaults),
            kSecAttrAccount as String: mimoAccountsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = copyKeychainItem(nonInteractiveKeychainQuery(query), item: &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func deleteMiMoAccountsKeychain(userDefaults: UserDefaults) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoAccountsService, userDefaults: userDefaults),
            kSecAttrAccount as String: mimoAccountsAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - MiMo ServiceToken (Keychain, keyed by account ID)

    private static let mimoTokenService = "ai-usage.mimo.service-token"
    private static let mimoTokenPresenceMirrorKey = "entitlement.mimo.tokenPresence.mirror"

    private static func mimoTokenKeyPrefix(forAccount accountID: UUID) -> String {
        "entitlement.mimo.account.\(accountID.uuidString).token."
    }

    static func mimoAccountIDsWithStoredToken(userDefaults: UserDefaults = .standard) -> Set<UUID> {
        let mirroredIDs = Set(
            (userDefaults.stringArray(forKey: mimoTokenPresenceMirrorKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
        if mirroredIDs.isEmpty == false {
            return mirroredIDs
        }
        return Set(
            mimoAccounts(userDefaults: userDefaults)
                .filter { account in
                    mimoServiceToken(forAccount: account.id, userDefaults: userDefaults) != nil
                }
                .map(\.id)
        )
    }

    static func mimoServiceToken(
        forAccount accountID: UUID,
        userDefaults: UserDefaults = .standard
    ) -> MiMoServiceToken? {
        if let data = readMiMoTokenKeychain(forAccount: accountID, userDefaults: userDefaults),
           let token = try? JSONDecoder().decode(MiMoServiceToken.self, from: data) {
            return token
        }

        let keyPrefix = mimoTokenKeyPrefix(forAccount: accountID)
        guard let serviceToken = userDefaults.string(forKey: keyPrefix + "serviceToken"),
              let userId = userDefaults.string(forKey: keyPrefix + "userId"),
              let slh = userDefaults.string(forKey: keyPrefix + "slh"),
              let ph = userDefaults.string(forKey: keyPrefix + "ph") else { return nil }
        let acquiredAt = userDefaults.object(forKey: keyPrefix + "acquiredAt") as? Date ?? Date()
        let migrated = MiMoServiceToken(
            serviceToken: serviceToken,
            userId: userId,
            slh: slh,
            ph: ph,
            acquiredAt: acquiredAt
        )
        setMiMoServiceToken(migrated, forAccount: accountID, userDefaults: userDefaults)
        return migrated
    }

    static func setMiMoServiceToken(
        _ token: MiMoServiceToken,
        forAccount accountID: UUID,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        deleteMiMoTokenKeychain(forAccount: accountID, userDefaults: userDefaults)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoTokenService, userDefaults: userDefaults),
            kSecAttrAccount as String: accountID.uuidString,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        clearLegacyMiMoServiceToken(forAccount: accountID, userDefaults: userDefaults)
        setMiMoTokenPresence(true, forAccount: accountID, userDefaults: userDefaults)
    }

    static func clearMiMoServiceToken(
        forAccount accountID: UUID,
        userDefaults: UserDefaults = .standard
    ) {
        deleteMiMoTokenKeychain(forAccount: accountID, userDefaults: userDefaults)
        clearLegacyMiMoServiceToken(forAccount: accountID, userDefaults: userDefaults)
        setMiMoTokenPresence(false, forAccount: accountID, userDefaults: userDefaults)
    }

    private static func setMiMoTokenPresence(_ isPresent: Bool, forAccount accountID: UUID, userDefaults: UserDefaults) {
        var ids = mimoAccountIDsWithStoredToken(userDefaults: userDefaults)
        if isPresent {
            ids.insert(accountID)
        } else {
            ids.remove(accountID)
        }
        let values = ids.map(\.uuidString).sorted()
        if values.isEmpty {
            userDefaults.removeObject(forKey: mimoTokenPresenceMirrorKey)
        } else {
            userDefaults.set(values, forKey: mimoTokenPresenceMirrorKey)
        }
    }

    private static func readMiMoTokenKeychain(forAccount accountID: UUID, userDefaults: UserDefaults) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoTokenService, userDefaults: userDefaults),
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = copyKeychainItem(nonInteractiveKeychainQuery(query), item: &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func deleteMiMoTokenKeychain(forAccount accountID: UUID, userDefaults: UserDefaults) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(mimoTokenService, userDefaults: userDefaults),
            kSecAttrAccount as String: accountID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func clearLegacyMiMoServiceToken(forAccount accountID: UUID, userDefaults: UserDefaults) {
        let keyPrefix = mimoTokenKeyPrefix(forAccount: accountID)
        userDefaults.removeObject(forKey: keyPrefix + "serviceToken")
        userDefaults.removeObject(forKey: keyPrefix + "userId")
        userDefaults.removeObject(forKey: keyPrefix + "slh")
        userDefaults.removeObject(forKey: keyPrefix + "ph")
        userDefaults.removeObject(forKey: keyPrefix + "acquiredAt")
    }

    private static func keychainService(_ service: String, userDefaults: UserDefaults) -> String {
        let namespace = (userDefaults.string(forKey: mimoKeychainNamespaceKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard namespace.isEmpty == false else { return service }
        return "\(service).\(namespace)"
    }

    private static func nonInteractiveKeychainQuery(_ query: [String: Any]) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }

    private static func copyKeychainItem(_ query: [String: Any], item: inout CFTypeRef?) -> OSStatus {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var status: OSStatus = errSecInternalError
            var item: CFTypeRef?
        }
        final class QueryBox: @unchecked Sendable {
            let query: CFDictionary

            init(_ query: [String: Any]) {
                self.query = query as CFDictionary
            }
        }
        let box = Box()
        let queryBox = QueryBox(query)
        DispatchQueue.global(qos: .userInitiated).async {
            var result: CFTypeRef?
            box.status = SecItemCopyMatching(queryBox.query, &result)
            box.item = result
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 0.5) == .success else {
            return errSecInteractionNotAllowed
        }
        item = box.item
        return box.status
    }
}

private struct MiMoAccountMirror: Codable {
    let id: UUID
    let username: String
    let displayName: String
    let email: String?
    let phone: String?
    let platformEmail: String?
    let planName: String?
}
