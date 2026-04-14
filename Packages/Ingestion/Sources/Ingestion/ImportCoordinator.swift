import Foundation
import Domain
import ParserCore

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
            let parsed = parser.parse(files: files)
            let source = SourceDescriptor(id: parser.sourceID, displayName: parser.displayName)
            let normalized = ImportNormalizer.makeBatch(source: source, files: files, parsed: parsed)
            let deduped = try await deduplicator.dedupe(batch: normalized)
            let run = try await persistence.persist(batch: deduped, trigger: request.trigger)
            lastRun = run
            sourceResults.append(SourceImportResult(
                id: source.id,
                sourceID: source.id,
                discoveredFiles: files.count,
                parsedEvents: parsed.events.count,
                parsedSessions: parsed.sessions.count,
                insertedEvents: deduped.events.count,
                insertedSessions: deduped.sessions.count,
                diagnostics: deduped.diagnostics,
                status: run.status
            ))
        }

        return ImportResult(run: lastRun, sourceResults: sourceResults)
    }
}
