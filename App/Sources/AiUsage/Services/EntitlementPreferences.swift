import Foundation

enum EntitlementPreferences {
    private static let prefix = "entitlement.target."
    private static let legacyOverviewMigrationKey = "entitlement.target.overview.legacyMigrated"

    static func descriptorTargets(providerPreferences: [ProviderPreferenceSnapshot]) -> [EntitlementTargetDescriptor] {
        [EntitlementTargetDescriptor(targetID: .overview, name: "总览", supportsOfficial: false)] + providerPreferences.map {
            EntitlementTargetDescriptor(
                targetID: .provider($0.id),
                name: $0.name,
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
        let selectedSource = EntitlementSourceSelection(rawValue: userDefaults.string(forKey: keyPrefix + "selectedSource") ?? "none") ?? .none
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
}
