import XCTest
@testable import ParserCore

final class ParserCoreTests: XCTestCase {
    func testClaudeParserParsesFixture() throws {
        let parser = ClaudeCodeParser()
        let file = try fixtureURL(path: "claude/session", ext: "jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.totalTokens, 2600)
        XCTAssertEqual(result.diagnostics.count, 0)
    }

    func testCodexParserParsesFixture() throws {
        let parser = CodexParser()
        let file = try fixtureURL(path: "codex/rollout", ext: "jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.project, "project-a")
        XCTAssertEqual(result.diagnostics.count, 0)
    }

    func testOpenCodeParserParsesFixture() throws {
        let parser = OpenCodeParser()
        let file = try fixtureURL(path: "opencode/msg_1", ext: "json")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.first?.totalTokens, 900)
    }

    func testGeminiParserParsesFixture() throws {
        let parser = GeminiParser()
        let file = try fixtureURL(path: "gemini/session-1", ext: "json")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.first?.totalTokens, 2200)
    }

    func testStableIDsAreDeterministicWithinParserRun() throws {
        let parser = ClaudeCodeParser()
        let file = try fixtureURL(path: "claude/session", ext: "jsonl")
        let first = parser.parse(files: [file])
        let second = parser.parse(files: [file])
        XCTAssertEqual(first.events.map(\ .id), second.events.map(\ .id))
        XCTAssertEqual(first.sessions.map(\ .id), second.sessions.map(\ .id))
    }

    private func fixtureURL(path: String, ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: path, withExtension: ext) else {
            throw XCTSkip("Missing fixture: \(path).\(ext)")
        }
        return url
    }
}
