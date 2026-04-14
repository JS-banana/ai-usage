import Foundation

public protocol SourceStore: Sendable {
    func write(sources: [SourceRecord]) async throws
    func write(sourceFiles: [SourceFileRecord]) async throws
}
