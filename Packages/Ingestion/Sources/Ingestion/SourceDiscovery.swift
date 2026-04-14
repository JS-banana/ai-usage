import Foundation
import ParserCore

public struct DefaultSourceDiscovery: SourceDiscovering {
    public init() {}

    public func discoverFiles(using parser: any UsageParser) -> [URL] {
        parser.discoverCandidates()
    }
}
