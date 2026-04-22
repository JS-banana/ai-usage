import Foundation
import Domain
import Support

public protocol UsageParser: Sendable {
    var sourceID: String { get }
    var displayName: String { get }
    func discoverCandidates() -> [URL]
    func parse(files: [URL]) -> ParsedFileResult
}

public enum ParserSessionBuilder {
    public static func buildSession(source: String, model: String, project: String, filePath: String, events: [UsageEvent]) -> SessionSummary? {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return SessionSummary(
            id: StableID.make([source, filePath, "session"]),
            source: source,
            model: model,
            project: project,
            startedAt: first.timestamp,
            endedAt: last.timestamp,
            messages: sorted.count,
            totalTokens: sorted.reduce(0) { $0 + $1.totalTokens },
            filePath: filePath
        )
    }
}
