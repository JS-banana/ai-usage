import Foundation
import GRDB

public final class DatabaseManager: @unchecked Sendable {
    public let configuration: PersistenceConfiguration
    public let dbQueue: DatabaseQueue

    public init(configuration: PersistenceConfiguration) throws {
        self.configuration = configuration
        let fileURL = URL(fileURLWithPath: configuration.location.path)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.dbQueue = try DatabaseQueue(path: fileURL.path)
        try PersistenceMigrator.makeMigrator().migrate(dbQueue)
    }
}
