import Foundation
import ProviderKit

struct ProviderPreferenceSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
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
            subtitle: "控制该来源是否显示在 usage 统计中",
            isEnabled: isSourceEnabled(descriptor.id, userDefaults: userDefaults)
        )
    }
}
