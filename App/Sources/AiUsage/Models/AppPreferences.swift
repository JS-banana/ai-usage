import Foundation
import ProviderKit

struct ProviderPreferenceSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let supportsQuota: Bool
    let isEnabled: Bool
}

enum AppPreferences {
    private static let sourceVisibilityPrefix = "ui.visibleSource."

    static func isSourceEnabled(_ sourceID: String, userDefaults: UserDefaults = .standard) -> Bool {
        let key = sourceVisibilityPrefix + sourceID
        guard userDefaults.object(forKey: key) != nil else { return true }
        return userDefaults.bool(forKey: key)
    }

    static func setSourceEnabled(_ enabled: Bool, sourceID: String, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: sourceVisibilityPrefix + sourceID)
    }

    static func preferenceSnapshot(
        for descriptor: ProviderDescriptor,
        userDefaults: UserDefaults = .standard
    ) -> ProviderPreferenceSnapshot {
        ProviderPreferenceSnapshot(
            id: descriptor.id,
            name: descriptor.displayName,
            subtitle: descriptor.capabilities.contains(.accountQuotaSnapshots)
                ? "可显示 usage，并支持分组额度配置"
                : "仅显示本地 usage 统计",
            supportsQuota: descriptor.capabilities.contains(.accountQuotaSnapshots),
            isEnabled: isSourceEnabled(descriptor.id, userDefaults: userDefaults)
        )
    }
}
