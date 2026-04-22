import XCTest
@testable import ParserCore

final class ParserCoreTests: XCTestCase {
    func testClaudeParserParsesFixture() throws {
        let parser = ClaudeCodeParser()
        let file = try fixtureURL(path: "claude/session", ext: "jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.map(\.totalTokens), [1700, 1200])
        XCTAssertEqual(result.events.map(\.cachedTokens), [200, 100])
        XCTAssertEqual(result.sessions.first?.totalTokens, 2900)
        XCTAssertEqual(result.diagnostics.count, 0)
    }

    func testClaudeParserSkipsSyntheticZeroTokenMessages() throws {
        let parser = ClaudeCodeParser()
        let file = try makeTemporaryFile(
            contents: """
            {"type":"assistant","timestamp":"2026-04-22T03:48:23.770Z","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0}}}
            {"type":"assistant","timestamp":"2026-04-22T03:49:23.770Z","message":{"model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":2}}}
            """,
            ext: "jsonl"
        )

        let result = parser.parse(files: [file])

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.first?.model, "claude-sonnet-4")
        XCTAssertEqual(result.events.first?.totalTokens, 17)
    }

    func testCodexParserParsesFixture() throws {
        let parser = CodexParser()
        let file = try fixtureURL(path: "codex/rollout", ext: "jsonl")
        let result = parser.parse(files: [file])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.map(\.totalTokens), [1650, 875])
        XCTAssertEqual(result.events.map(\.cachedTokens), [50, 25])
        XCTAssertEqual(result.sessions.first?.totalTokens, 2525)
        XCTAssertEqual(result.sessions.first?.project, "project-a")
        XCTAssertEqual(result.diagnostics.count, 0)
    }

    func testCodexParserParsesRealEventMsgTokenCountShape() throws {
        let parser = CodexParser()
        let file = try makeTemporaryFile(
            contents: """
            {"timestamp":"2025-11-25T01:51:55.895Z","type":"session_meta","payload":{"cwd":"/Users/demo/project-real","model_provider":"claudebuddy"}}
            {"timestamp":"2025-11-25T01:52:00.615Z","type":"turn_context","payload":{"cwd":"/Users/demo/project-real","model":"gpt-5.1-codex"}}
            {"timestamp":"2025-11-25T01:52:04.120Z","type":"event_msg","payload":{"type":"token_count","info":null}}
            {"timestamp":"2025-11-25T01:52:06.168Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3387,"cached_input_tokens":3072,"output_tokens":14,"total_tokens":6473},"last_token_usage":{"input_tokens":315,"cached_input_tokens":256,"output_tokens":14,"total_tokens":585}}}}
            """,
            ext: "jsonl"
        )

        let result = parser.parse(files: [file])

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.events.first?.model, "gpt-5.1-codex")
        XCTAssertEqual(result.events.first?.project, "project-real")
        XCTAssertEqual(result.events.first?.inputTokens, 315)
        XCTAssertEqual(result.events.first?.cachedTokens, 256)
        XCTAssertEqual(result.events.first?.outputTokens, 14)
        XCTAssertEqual(result.events.first?.totalTokens, 585)
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
        let nsPath = path as NSString
        let resource = nsPath.lastPathComponent
        let url = Bundle.module.url(forResource: resource, withExtension: ext)
        guard let url else {
            throw XCTSkip("Missing fixture: \(path).\(ext)")
        }
        return url
    }

    private func makeTemporaryFile(contents: String, ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("fixture.\(ext)")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
