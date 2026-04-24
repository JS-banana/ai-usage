import Foundation
import ProviderKit

public struct QuotaRefreshPlan: Sendable {
    public let providerIDs: [String]
    public let generatedAt: Date

    public init(providerIDs: [String], generatedAt: Date = Date()) {
        self.providerIDs = providerIDs
        self.generatedAt = generatedAt
    }
}

public actor QuotaRefreshCoordinator {
    private let registry: SourceRegistry

    public init(registry: SourceRegistry) {
        self.registry = registry
    }

    public func makePlan(providerIDs: [String]? = nil, generatedAt: Date = Date()) -> QuotaRefreshPlan {
        let eligible = registry.providerDescriptors()
            .filter { $0.capabilities.contains(.accountQuotaSnapshots) }
            .map(\.id)

        let plannedIDs: [String]
        if let providerIDs, providerIDs.isEmpty == false {
            let requested = Set(providerIDs)
            plannedIDs = eligible.filter { requested.contains($0) }
        } else {
            plannedIDs = eligible
        }

        return QuotaRefreshPlan(providerIDs: plannedIDs, generatedAt: generatedAt)
    }
}
