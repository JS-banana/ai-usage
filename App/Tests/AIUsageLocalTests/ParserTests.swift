import XCTest
@testable import AIUsageLocal

final class ParserTests: XCTestCase {
    func testClaudeParserParsesFixture() throws {
        let parser = ClaudeCodeParser()
        let file = URL(fileURLWithPath: "/tmp/ai-usage-local/ai-usage-local/Fixtures/claude/session.jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.totalTokens, 2600)
    }

    func testCodexParserParsesFixture() throws {
        let parser = CodexParser()
        let file = URL(fileURLWithPath: "/tmp/ai-usage-local/ai-usage-local/Fixtures/codex/rollout.jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.first?.project, "project-a")
    }

    func testOpenCodeParserParsesFixture() throws {
        let parser = OpenCodeParser()
        let file = URL(fileURLWithPath: "/tmp/ai-usage-local/ai-usage-local/Fixtures/opencode/msg_1.json")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.first?.totalTokens, 900)
    }

    func testGeminiParserParsesFixture() throws {
        let parser = GeminiParser()
        let file = URL(fileURLWithPath: "/tmp/ai-usage-local/ai-usage-local/Fixtures/gemini/session-1.json")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.first?.totalTokens, 2200)
    }
}
