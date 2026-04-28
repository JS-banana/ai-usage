import Foundation
import Domain

public enum ProviderCapability: String, Hashable, Sendable {
    case localUsageFacts
    case accountQuotaSnapshots
}

public enum ProviderBackendKind: String, Hashable, Sendable {
    case localLogs
    case remoteAPI
    case hybrid
}

public enum CredentialKind: String, Hashable, Sendable {
    case none
    case apiKey
    case accountSession
    case cliAuth
}

public enum RefreshPolicy: Hashable, Sendable {
    case manual
    case onAppLaunch
    case scheduled(minutes: Int)
}

public struct ProviderDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<ProviderCapability>
    public let backendKind: ProviderBackendKind
    public let credentialKind: CredentialKind
    public let refreshPolicy: RefreshPolicy
    public let builtIn: Bool
    public let enabledByDefault: Bool

    public init(
        id: String,
        displayName: String,
        capabilities: Set<ProviderCapability>,
        backendKind: ProviderBackendKind,
        credentialKind: CredentialKind,
        refreshPolicy: RefreshPolicy,
        builtIn: Bool = true,
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.backendKind = backendKind
        self.credentialKind = credentialKind
        self.refreshPolicy = refreshPolicy
        self.builtIn = builtIn
        self.enabledByDefault = enabledByDefault
    }

    public var sourceDescriptor: SourceDescriptor {
        SourceDescriptor(
            id: id,
            displayName: displayName,
            builtIn: builtIn,
            enabledByDefault: enabledByDefault
        )
    }
}
