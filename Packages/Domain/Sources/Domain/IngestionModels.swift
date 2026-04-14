import Foundation

public enum ImportTrigger: String, Sendable, Hashable {
    case manual
    case startup
    case background
}

public enum ImportRunStatus: String, Sendable, Hashable {
    case running
    case succeeded
    case failed
    case partial
}

public struct SourceDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let builtIn: Bool
    public let enabledByDefault: Bool

    public init(id: String, displayName: String, builtIn: Bool = true, enabledByDefault: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.builtIn = builtIn
        self.enabledByDefault = enabledByDefault
    }
}

public struct ImportRun: Identifiable, Hashable, Sendable {
    public let id: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: ImportRunStatus
    public let trigger: ImportTrigger
    public let totalFiles: Int
    public let totalEvents: Int
    public let totalSessions: Int
    public let skippedRecords: Int

    public init(id: String, startedAt: Date, finishedAt: Date? = nil, status: ImportRunStatus, trigger: ImportTrigger, totalFiles: Int, totalEvents: Int, totalSessions: Int, skippedRecords: Int) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.trigger = trigger
        self.totalFiles = max(0, totalFiles)
        self.totalEvents = max(0, totalEvents)
        self.totalSessions = max(0, totalSessions)
        self.skippedRecords = max(0, skippedRecords)
    }
}

public struct TrackedSourceFile: Identifiable, Hashable, Sendable {
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
