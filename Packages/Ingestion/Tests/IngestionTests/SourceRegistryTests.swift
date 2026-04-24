import XCTest
import Domain
import ParserCore
import ProviderKit
@testable import Ingestion

final class SourceRegistryTests: XCTestCase {
    func testDefaultRegistryExposesAllBuiltInParsers() {
        let registry = StaticSourceRegistry()
        XCTAssertEqual(registry.allSources().map(\.id), ["claude-code", "codex", "opencode", "gemini"])
        XCTAssertEqual(registry.enabledParsers().map(\.sourceID), ["claude-code", "codex", "opencode", "gemini"])
        let providers = registry.providerDescriptors()
        XCTAssertEqual(providers.map(\.displayName), ["Claude", "Codex", "OpenCode", "Gemini"])
        XCTAssertTrue(providers.allSatisfy { $0.capabilities.contains(.localUsageFacts) })
        XCTAssertEqual(providers.first(where: { $0.id == "claude-code" })?.backendKind, .hybrid)
        XCTAssertEqual(providers.first(where: { $0.id == "claude-code" })?.credentialKind, .apiKey)
        XCTAssertTrue(providers.first(where: { $0.id == "claude-code" })?.capabilities.contains(.accountQuotaSnapshots) == true)
        XCTAssertTrue(providers.filter { $0.id != "claude-code" }.allSatisfy { $0.backendKind == .localLogs })
        XCTAssertTrue(providers.filter { $0.id != "claude-code" }.allSatisfy { $0.credentialKind == .none })
    }

    func testQuotaRefreshCoordinatorPlansQuotaCapableProvidersOnly() async {
        let registry = StubSourceRegistry()
        let coordinator = QuotaRefreshCoordinator(registry: registry)

        let plan = await coordinator.makePlan()

        XCTAssertEqual(plan.providerIDs, ["quota-provider"])
    }
}

private struct StubSourceRegistry: SourceRegistry {
    func allSources() -> [SourceDescriptor] { providerDescriptors().map(\.sourceDescriptor) }

    func providerDescriptors() -> [ProviderDescriptor] {
        [
            ProviderDescriptor(
                id: "usage-only",
                displayName: "Usage Only",
                capabilities: [.localUsageFacts],
                backendKind: .localLogs,
                credentialKind: .none,
                refreshPolicy: .manual
            ),
            ProviderDescriptor(
                id: "quota-provider",
                displayName: "Quota Provider",
                capabilities: [.localUsageFacts, .accountQuotaSnapshots],
                backendKind: .remoteAPI,
                credentialKind: .apiKey,
                refreshPolicy: .manual
            )
        ]
    }

    func enabledParsers() -> [any UsageParser] { [] }
}
