import Foundation
import Domain
import ParserCore

public protocol SourceRegistry: Sendable {
    func allSources() -> [SourceDescriptor]
    func enabledParsers() -> [any UsageParser]
}

public protocol ImportPersistence: Sendable {
    func persist(batch: NormalizedImportBatch, trigger: ImportTrigger) async throws -> ImportRun
}

public protocol Deduplicating: Sendable {
    func dedupe(batch: NormalizedImportBatch) async throws -> NormalizedImportBatch
}

public protocol SourceDiscovering: Sendable {
    func discoverFiles(using parser: any UsageParser) -> [URL]
}
