import Foundation

public struct SchemaDefinition: Sendable {
    public let version: SchemaVersion
    public let tables: [String]

    public init(version: SchemaVersion = .v1, tables: [String] = [
        TableNames.sources,
        TableNames.sourceFiles,
        TableNames.importRuns,
        TableNames.usageEvents,
        TableNames.sessions,
        TableNames.parserDiagnostics,
        TableNames.dailyBuckets,
    ]) {
        self.version = version
        self.tables = tables
    }
}
