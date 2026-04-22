import Foundation
import Domain
import ParserCore
import Support

public struct StaticSourceRegistry: SourceRegistry {
    private let parsers: [any UsageParser]

    public init(parsers: [any UsageParser] = [
        ClaudeCodeParser(),
        CodexParser(),
    ]) {
        self.parsers = parsers
    }

    public func allSources() -> [SourceDescriptor] {
        parsers.map { SourceDescriptor(id: $0.sourceID, displayName: $0.displayName) }
    }

    public func enabledParsers() -> [any UsageParser] {
        parsers
    }
}
