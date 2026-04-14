import Foundation
import Domain

public struct ImportRunRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: ImportRunStatus
    public let trigger: ImportTrigger
    public let totalFiles: Int
    public let totalEvents: Int
    public let totalSessions: Int
    public let skippedRecords: Int

    public init(id: String, startedAt: Date, finishedAt: Date?, status: ImportRunStatus, trigger: ImportTrigger, totalFiles: Int, totalEvents: Int, totalSessions: Int, skippedRecords: Int) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.trigger = trigger
        self.totalFiles = totalFiles
        self.totalEvents = totalEvents
        self.totalSessions = totalSessions
        self.skippedRecords = skippedRecords
    }
}
