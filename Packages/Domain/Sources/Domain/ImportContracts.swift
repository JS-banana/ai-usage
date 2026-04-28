import Foundation

public struct ImportRequest: Sendable {
    public let sourceIDs: [String]?
    public let trigger: ImportTrigger
    public let startedAt: Date

    public init(sourceIDs: [String]? = nil, trigger: ImportTrigger, startedAt: Date = Date()) {
        self.sourceIDs = sourceIDs
        self.trigger = trigger
        self.startedAt = startedAt
    }
}

public struct SourceImportResult: Identifiable, Sendable {
    public let id: String
    public let sourceID: String
    public let discoveredFiles: Int
    public let parsedEvents: Int
    public let parsedSessions: Int
    public let insertedEvents: Int
    public let insertedSessions: Int
    public let diagnostics: [ParserDiagnostic]
    public let status: ImportRunStatus

    public init(id: String, sourceID: String, discoveredFiles: Int, parsedEvents: Int, parsedSessions: Int, insertedEvents: Int, insertedSessions: Int, diagnostics: [ParserDiagnostic], status: ImportRunStatus) {
        self.id = id
        self.sourceID = sourceID
        self.discoveredFiles = discoveredFiles
        self.parsedEvents = parsedEvents
        self.parsedSessions = parsedSessions
        self.insertedEvents = insertedEvents
        self.insertedSessions = insertedSessions
        self.diagnostics = diagnostics
        self.status = status
    }
}

public struct ImportResult: Sendable {
    public let run: ImportRun
    public let sourceResults: [SourceImportResult]

    public init(run: ImportRun, sourceResults: [SourceImportResult]) {
        self.run = run
        self.sourceResults = sourceResults
    }
}

public struct NormalizedImportBatch: Sendable {
    public let source: SourceDescriptor
    public let sourceFiles: [TrackedSourceFile]
    public let events: [UsageEvent]
    public let sessions: [SessionSummary]
    public let diagnostics: [ParserDiagnostic]
    public let skippedRecords: Int

    public init(source: SourceDescriptor, sourceFiles: [TrackedSourceFile], events: [UsageEvent], sessions: [SessionSummary], diagnostics: [ParserDiagnostic], skippedRecords: Int) {
        self.source = source
        self.sourceFiles = sourceFiles
        self.events = events
        self.sessions = sessions
        self.diagnostics = diagnostics
        self.skippedRecords = skippedRecords
    }
}

public protocol ImportPersistence: Sendable {
    func unchangedFilePaths(sourceID: String, fingerprintsByPath: [String: String]) async throws -> Set<String>
    func persist(batch: NormalizedImportBatch, trigger: ImportTrigger) async throws -> ImportRun
}
