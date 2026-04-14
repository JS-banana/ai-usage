import Foundation

public protocol DatabaseWriter: Sendable {
    func writeImportBatch(_ batch: PersistedImportBatch) async throws -> ImportWriteResult
}
