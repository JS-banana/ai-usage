import Foundation
import Domain

public struct PersistedImportBatch: Sendable {
    public let importRun: ImportRun
    public let sources: [SourceRecord]
    public let sourceFiles: [SourceFileRecord]
    public let events: [UsageEvent]
    public let sessions: [SessionSummary]
    public let diagnostics: [ParserDiagnostic]

    public init(importRun: ImportRun, sources: [SourceRecord], sourceFiles: [SourceFileRecord], events: [UsageEvent], sessions: [SessionSummary], diagnostics: [ParserDiagnostic]) {
        self.importRun = importRun
        self.sources = sources
        self.sourceFiles = sourceFiles
        self.events = events
        self.sessions = sessions
        self.diagnostics = diagnostics
    }
}
