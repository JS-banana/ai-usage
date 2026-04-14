import Foundation

public struct PersistenceConfiguration: Sendable {
    public let location: DatabaseLocation
    public let schemaVersion: SchemaVersion

    public init(location: DatabaseLocation, schemaVersion: SchemaVersion = .v1) {
        self.location = location
        self.schemaVersion = schemaVersion
    }
}
