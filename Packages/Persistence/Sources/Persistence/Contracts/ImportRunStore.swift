import Foundation

public protocol ImportRunStore: Sendable {
    func latestRunID() async throws -> String?
}
