import Foundation
import Domain
import ParserCore
import Support

public struct NoOpDeduplicator: Deduplicating {
    public init() {}

    public func dedupe(batch: NormalizedImportBatch) async throws -> NormalizedImportBatch {
        batch
    }
}

public enum ImportNormalizer {
    public static func makeBatch(source: SourceDescriptor, files: [URL], parsed: ParsedFileResult) -> NormalizedImportBatch {
        let trackedFiles = files.map {
            TrackedSourceFile(
                id: StableID.make([source.id, $0.path, "tracked-file"]),
                sourceID: source.id,
                path: $0.path,
                fingerprint: StableID.make([$0.path, "placeholder-fingerprint"]),
                lastSeenAt: Date(),
                lastImportRunID: nil
            )
        }
        return NormalizedImportBatch(
            source: source,
            sourceFiles: trackedFiles,
            events: parsed.events,
            sessions: parsed.sessions,
            diagnostics: parsed.diagnostics,
            skippedRecords: parsed.skippedRecords
        )
    }
}
