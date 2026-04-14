import Foundation
import Domain

public protocol DiagnosticStore: Sendable {
    func write(diagnostics: [ParserDiagnostic]) async throws
}
