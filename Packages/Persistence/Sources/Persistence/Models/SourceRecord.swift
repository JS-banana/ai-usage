import Foundation

public struct SourceRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let enabled: Bool
    public let builtIn: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, displayName: String, enabled: Bool, builtIn: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.enabled = enabled
        self.builtIn = builtIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
