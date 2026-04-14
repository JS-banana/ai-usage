import Foundation
import Domain

public struct SessionDetail: Identifiable, Hashable, Sendable {
    public let id: String
    public let summary: SessionSummary
    public let diagnostics: [ParserDiagnostic]

    public init(id: String, summary: SessionSummary, diagnostics: [ParserDiagnostic] = []) {
        self.id = id
        self.summary = summary
        self.diagnostics = diagnostics
    }
}
