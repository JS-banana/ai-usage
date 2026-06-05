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
    case mimo

    var id: String { rawValue }
}

enum EntitlementSourceKind: String, Hashable, Sendable {
    case official
    case thirdParty
    case mimo
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
    let detailText: String
    let primaryText: String
    let secondaryText: String
    let footnoteText: String
    let progress: Double?

    init(
        id: String,
        title: String,
        detailText: String = "",
        primaryText: String,
        secondaryText: String,
        footnoteText: String,
        progress: Double?
    ) {
        self.id = id
        self.title = title
        self.detailText = detailText
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.footnoteText = footnoteText
        self.progress = progress
    }

    var isVisible: Bool {
        title.isEmpty == false
            || detailText.isEmpty == false
            || primaryText.isEmpty == false
            || secondaryText.isEmpty == false
            || footnoteText.isEmpty == false
            || progress != nil
    }

    static func hidden(id: String) -> EntitlementWindowSnapshot {
        EntitlementWindowSnapshot(
            id: id,
            title: "",
            primaryText: "",
            secondaryText: "",
            footnoteText: "",
            progress: nil
        )
    }
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
    let extraWindows: [EntitlementWindowSnapshot]
    let menuBarProgress: Double?

    init(
        targetID: EntitlementTargetID,
        title: String,
        message: String,
        updatedAt: Date?,
        status: EntitlementSummaryStatus,
        sourceKind: EntitlementSourceKind?,
        provenance: EntitlementProvenance,
        derivedFromTitle: String?,
        primaryWindow: EntitlementWindowSnapshot,
        secondaryWindow: EntitlementWindowSnapshot,
        extraWindows: [EntitlementWindowSnapshot] = [],
        menuBarProgress: Double? = nil
    ) {
        self.targetID = targetID
        self.title = title
        self.message = message
        self.updatedAt = updatedAt
        self.status = status
        self.sourceKind = sourceKind
        self.provenance = provenance
        self.derivedFromTitle = derivedFromTitle
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.extraWindows = extraWindows
        self.menuBarProgress = menuBarProgress
    }

    var isDerived: Bool { provenance == .derived }

    var visibleWindows: [EntitlementWindowSnapshot] {
        ([primaryWindow, secondaryWindow] + extraWindows).filter(\.isVisible)
    }

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
