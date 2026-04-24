import Foundation
import Domain
import ParserCore
import Support
import ProviderKit

public actor ImportCoordinator {
    private let registry: SourceRegistry
    private let discovery: SourceDiscovering
    private let deduplicator: Deduplicating
    private let persistence: ImportPersistence

    public init(
        registry: SourceRegistry,
        discovery: SourceDiscovering,
        deduplicator: Deduplicating,
        persistence: ImportPersistence
    ) {
        self.registry = registry
        self.discovery = discovery
        self.deduplicator = deduplicator
        self.persistence = persistence
    }

    public func runImport(request: ImportRequest) async throws -> ImportResult {
        let parsers = registry.enabledParsers().filter { parser in
            guard let sourceIDs = request.sourceIDs, sourceIDs.isEmpty == false else { return true }
            return sourceIDs.contains(parser.sourceID)
        }
        let providerByID = Dictionary(uniqueKeysWithValues: registry.providerDescriptors().map { ($0.id, $0) })

        var sourceResults: [SourceImportResult] = []
        var lastRun = ImportRun(
            id: "pending",
            startedAt: request.startedAt,
            finishedAt: nil,
            status: .running,
            trigger: request.trigger,
            totalFiles: 0,
            totalEvents: 0,
            totalSessions: 0,
            skippedRecords: 0
        )

        for parser in parsers {
            let files = discovery.discoverFiles(using: parser)
            let source = providerByID[parser.sourceID]?.sourceDescriptor
                ?? SourceDescriptor(id: parser.sourceID, displayName: parser.displayName)
            let fingerprintsByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, FileFingerprint.metadataSignature(for: $0)) })
            let unchangedPaths = try await persistence.unchangedFilePaths(sourceID: source.id, fingerprintsByPath: fingerprintsByPath)
            let filesToParse = files.filter { unchangedPaths.contains($0.path) == false }
            let parsed = parser.parse(files: filesToParse)
            let normalized = ImportNormalizer.makeBatch(source: source, files: files, parsed: parsed, seenAt: request.startedAt)
            let deduped = try await deduplicator.dedupe(batch: normalized)
            let run = try await persistence.persist(batch: deduped, trigger: request.trigger)
            lastRun = run
            sourceResults.append(SourceImportResult(
                id: source.id,
                sourceID: source.id,
                discoveredFiles: files.count,
                parsedEvents: parsed.events.count,
                parsedSessions: parsed.sessions.count,
                insertedEvents: run.totalEvents,
                insertedSessions: run.totalSessions,
                diagnostics: deduped.diagnostics,
                status: run.status
            ))
        }

        return ImportResult(run: lastRun, sourceResults: sourceResults)
    }
}
