import Foundation
import Domain

public protocol UsageEventStore: Sendable {
    func existingEventIDs() async throws -> Set<String>
    func write(events: [UsageEvent]) async throws
}
