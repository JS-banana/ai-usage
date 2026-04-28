import Foundation
import Domain

enum ProviderBrandAccentToken: String, Hashable, Sendable {
    case overview
    case claude
    case codex
    case gemini
    case opencode
    case antigravity
    case generic
}

struct ProviderBrandColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

struct ProviderLogoResource: Hashable, Sendable {
    let name: String
    let fileExtension: String
    let subdirectory: String

    init(name: String, fileExtension: String = "svg", subdirectory: String = "Brand") {
        self.name = name
        self.fileExtension = fileExtension
        self.subdirectory = subdirectory
    }
}

enum ProviderTabFallbackIcon: Hashable, Sendable {
    case symbol(String)
    case monogram(String)
}

struct ProviderTabBranding: Hashable, Sendable {
    let accentToken: ProviderBrandAccentToken
    let accentColor: ProviderBrandColor
    let logoResource: ProviderLogoResource?
    let fallbackIcon: ProviderTabFallbackIcon
}

struct ProviderTabItem: Identifiable, Sendable {
    let id: String
    let name: String
    let status: SourceStatus
    let branding: ProviderTabBranding
    let usageProgress: Double?

    var isOverview: Bool { id == "overview" }
}
