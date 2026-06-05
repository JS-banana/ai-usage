import Foundation
import Domain
import ParserCore
import ProviderKit
import Support

public struct StaticSourceRegistry: SourceRegistry {
    private let parsers: [any UsageParser]
    private let providers: [ProviderDescriptor]

    public init(parsers: [any UsageParser] = [
        ClaudeCodeParser(),
        CodexParser(),
        OpenCodeParser(),
        GeminiParser(),
    ]) {
        self.parsers = parsers
        self.providers = Self.makeProviders(from: parsers)
    }

    public func allSources() -> [SourceDescriptor] {
        providers.map(\.sourceDescriptor)
    }

    public func providerDescriptors() -> [ProviderDescriptor] {
        providers
    }

    public func enabledParsers() -> [any UsageParser] {
        parsers
    }

    private static func makeProviders(from parsers: [any UsageParser]) -> [ProviderDescriptor] {
        let parserProviders = parsers.map { parser in
            ProviderDescriptor(
                id: parser.sourceID,
                displayName: displayName(for: parser.sourceID, fallback: parser.displayName),
                capabilities: capabilities(for: parser.sourceID),
                backendKind: backendKind(for: parser.sourceID),
                credentialKind: credentialKind(for: parser.sourceID),
                refreshPolicy: .manual
            )
        }
        let virtualProviders = [
            ProviderDescriptor(
                id: "mimo",
                displayName: "MiMo",
                capabilities: [.accountQuotaSnapshots],
                backendKind: .remoteAPI,
                credentialKind: .accountSession,
                refreshPolicy: .manual
            ),
        ]
        return parserProviders + virtualProviders
    }

    private static func displayName(for sourceID: String, fallback: String) -> String {
        switch sourceID {
        case "claude-code": return "Claude"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "gemini": return "Gemini"
        default: return fallback
        }
    }

    private static func capabilities(for sourceID: String) -> Set<ProviderCapability> {
        switch sourceID {
        case "claude-code":
            return [.localUsageFacts, .accountQuotaSnapshots]
        default:
            return [.localUsageFacts]
        }
    }

    private static func backendKind(for sourceID: String) -> ProviderBackendKind {
        switch sourceID {
        case "claude-code":
            return .hybrid
        default:
            return .localLogs
        }
    }

    private static func credentialKind(for sourceID: String) -> CredentialKind {
        switch sourceID {
        case "claude-code":
            return .apiKey
        default:
            return .none
        }
    }
}
