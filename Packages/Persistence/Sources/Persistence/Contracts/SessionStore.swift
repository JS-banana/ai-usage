import Foundation
import Domain

public protocol SessionStore: Sendable {
    func write(sessions: [SessionSummary]) async throws
}
