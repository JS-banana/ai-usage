import Foundation

public struct SourceFileRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let sourceID: String
    public let path: String
    public let fingerprint: String
    public let lastSeenAt: Date
    public let lastImportRunID: String?

    public init(id: String, sourceID: String, path: String, fingerprint: String, lastSeenAt: Date, lastImportRunID: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.path = path
        self.fingerprint = fingerprint
        self.lastSeenAt = lastSeenAt
        self.lastImportRunID = lastImportRunID
    }
}
