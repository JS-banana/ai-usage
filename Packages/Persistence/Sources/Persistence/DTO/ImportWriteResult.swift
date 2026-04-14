import Foundation

public struct ImportWriteResult: Sendable {
    public let insertedEvents: Int
    public let insertedSessions: Int
    public let insertedDiagnostics: Int
    public let skippedDuplicates: Int

    public init(insertedEvents: Int, insertedSessions: Int, insertedDiagnostics: Int, skippedDuplicates: Int) {
        self.insertedEvents = max(0, insertedEvents)
        self.insertedSessions = max(0, insertedSessions)
        self.insertedDiagnostics = max(0, insertedDiagnostics)
        self.skippedDuplicates = max(0, skippedDuplicates)
    }
}
