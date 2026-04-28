import Foundation
import Domain
import ParserCore
import ProviderKit

public protocol SourceRegistry: Sendable {
    func allSources() -> [SourceDescriptor]
    func providerDescriptors() -> [ProviderDescriptor]
    func enabledParsers() -> [any UsageParser]
}

public protocol Deduplicating: Sendable {
    func dedupe(batch: NormalizedImportBatch) async throws -> NormalizedImportBatch
}

public protocol SourceDiscovering: Sendable {
    func discoverFiles(using parser: any UsageParser) -> [URL]
}
