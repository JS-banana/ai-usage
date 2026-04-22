import XCTest
@testable import Ingestion

final class SourceRegistryTests: XCTestCase {
    func testDefaultRegistryExposesClaudeAndCodexOnlyForV1() {
        let registry = StaticSourceRegistry()
        XCTAssertEqual(registry.allSources().map(\.id), ["claude-code", "codex"])
        XCTAssertEqual(registry.enabledParsers().map(\.sourceID), ["claude-code", "codex"])
    }
}
