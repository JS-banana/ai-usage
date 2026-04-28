import Foundation

enum ProviderBrandCatalog {
    static func branding(for providerID: String, fallbackName: String) -> ProviderTabBranding {
        if let branding = knownBranding(for: providerID) {
            return branding
        }

        return ProviderTabBranding(
            accentToken: .generic,
            accentColor: ProviderBrandColor(red: 0.56, green: 0.56, blue: 0.58),
            logoResource: nil,
            fallbackIcon: fallbackName.isEmpty ? .symbol("circle.hexagongrid.fill") : .monogram(String(fallbackName.prefix(1)).uppercased())
        )
    }

    private static func knownBranding(for providerID: String) -> ProviderTabBranding? {
        switch providerID {
        case "overview":
            ProviderTabBranding(
                accentToken: .overview,
                accentColor: ProviderBrandColor(red: 0.56, green: 0.56, blue: 0.58),
                logoResource: nil,
                fallbackIcon: .symbol("square.grid.2x2.fill")
            )
        case "claude-code":
            brandedProvider(
                token: .claude,
                color: ProviderBrandColor(red: 204.0 / 255.0, green: 124.0 / 255.0, blue: 94.0 / 255.0),
                resourceName: "ProviderIcon-claude",
                fallbackIcon: .monogram("✺")
            )
        case "codex":
            brandedProvider(
                token: .codex,
                color: ProviderBrandColor(red: 73.0 / 255.0, green: 163.0 / 255.0, blue: 176.0 / 255.0),
                resourceName: "ProviderIcon-codex",
                fallbackIcon: .monogram("◎")
            )
        case "gemini":
            brandedProvider(
                token: .gemini,
                color: ProviderBrandColor(red: 171.0 / 255.0, green: 135.0 / 255.0, blue: 234.0 / 255.0),
                resourceName: "ProviderIcon-gemini",
                fallbackIcon: .symbol("sparkles")
            )
        case "opencode":
            brandedProvider(
                token: .opencode,
                color: ProviderBrandColor(red: 59.0 / 255.0, green: 130.0 / 255.0, blue: 246.0 / 255.0),
                resourceName: "ProviderIcon-opencode",
                fallbackIcon: .monogram("</>")
            )
        case "antigravity":
            brandedProvider(
                token: .antigravity,
                color: ProviderBrandColor(red: 96.0 / 255.0, green: 186.0 / 255.0, blue: 126.0 / 255.0),
                resourceName: "ProviderIcon-antigravity",
                fallbackIcon: .monogram("A")
            )
        default:
            nil
        }
    }

    private static func brandedProvider(
        token: ProviderBrandAccentToken,
        color: ProviderBrandColor,
        resourceName: String,
        fallbackIcon: ProviderTabFallbackIcon
    ) -> ProviderTabBranding {
        ProviderTabBranding(
            accentToken: token,
            accentColor: color,
            logoResource: ProviderLogoResource(name: resourceName),
            fallbackIcon: fallbackIcon
        )
    }
}
