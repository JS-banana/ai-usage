import Foundation

enum EntitlementTargetID: Hashable, Sendable {
    case overview
    case provider(String)

    init(storageKey: String) {
        if storageKey == "overview" {
            self = .overview
        } else {
            self = .provider(storageKey)
        }
    }

    var storageKey: String {
        switch self {
        case .overview:
            return "overview"
        case .provider(let providerID):
            return providerID
        }
    }
}

enum EntitlementSourceSelection: String, CaseIterable, Identifiable, Sendable {
    case none
    case official
    case thirdParty

    var id: String { rawValue }
}

enum EntitlementSourceKind: String, Hashable, Sendable {
    case official
    case thirdParty
}

enum EntitlementSummaryStatus: String, Hashable, Sendable {
    case ready
    case stale
    case failed
    case unconfigured
    case configuredNonlive
    case unavailable
}

enum EntitlementProvenance: Hashable, Sendable {
    case explicit
    case derived
}

struct BridgeEntitlementConfiguration: Hashable, Sendable {
    let endpointURL: URL
    let apiKey: String
}

struct EntitlementTargetConfiguration: Hashable, Sendable {
    let targetID: EntitlementTargetID
    let selectedSource: EntitlementSourceSelection
    let bridgeConfiguration: BridgeEntitlementConfiguration?
}

struct EntitlementWindowSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let primaryText: String
    let secondaryText: String
    let footnoteText: String
    let progress: Double?
}

struct EntitlementSummarySnapshot: Hashable, Sendable {
    let targetID: EntitlementTargetID
    let title: String
    let message: String
    let updatedAt: Date?
    let status: EntitlementSummaryStatus
    let sourceKind: EntitlementSourceKind?
    let provenance: EntitlementProvenance
    let derivedFromTitle: String?
    let primaryWindow: EntitlementWindowSnapshot
    let secondaryWindow: EntitlementWindowSnapshot

    var isDerived: Bool { provenance == .derived }

    static func placeholder(
        targetID: EntitlementTargetID,
        title: String,
        message: String,
        status: EntitlementSummaryStatus,
        sourceKind: EntitlementSourceKind?,
        provenance: EntitlementProvenance = .explicit,
        derivedFromTitle: String? = nil,
        primaryTitle: String = "5h",
        secondaryTitle: String = "7d",
        primaryText: String,
        secondaryText: String,
        footnote: String
    ) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot(
            targetID: targetID,
            title: title,
            message: message,
            updatedAt: nil,
            status: status,
            sourceKind: sourceKind,
            provenance: provenance,
            derivedFromTitle: derivedFromTitle,
            primaryWindow: EntitlementWindowSnapshot(
                id: "\(targetID.storageKey)-primary",
                title: primaryTitle,
                primaryText: primaryText,
                secondaryText: secondaryText,
                footnoteText: footnote,
                progress: nil
            ),
            secondaryWindow: EntitlementWindowSnapshot(
                id: "\(targetID.storageKey)-secondary",
                title: secondaryTitle,
                primaryText: primaryText,
                secondaryText: secondaryText,
                footnoteText: footnote,
                progress: nil
            )
        )
    }
}

struct EntitlementTargetDescriptor: Identifiable, Hashable, Sendable {
    let targetID: EntitlementTargetID
    let name: String
    let supportsOfficial: Bool

    var id: String { targetID.storageKey }
}
