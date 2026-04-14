import Foundation
import Domain
import Support

public struct GeminiParser: UsageParser {
    public let sourceID = "gemini"
    public let displayName = "Gemini CLI"

    public init() {}

    public func discoverCandidates() -> [URL] {
        FileDiscovery.listFiles(recursive: FileDiscovery.expandHome("~/.gemini/tmp"), suffixes: [".json", ".jsonl"])
    }

    public func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var sessions: [SessionSummary] = []
        var diagnostics: [ParserDiagnostic] = []
        var skippedRecords = 0

        for file in files where file.lastPathComponent.contains("session") || file.deletingLastPathComponent().path.contains("chats") {
            guard let data = try? Data(contentsOf: file) else {
                diagnostics.append(ParserDiagnosticsFactory.error(source: sourceID, filePath: file.path, message: "无法读取文件"))
                continue
            }
            let result = parseSessionFile(data: data, file: file)
            events.append(contentsOf: result.events)
            sessions.append(contentsOf: result.sessions)
            diagnostics.append(contentsOf: result.diagnostics)
            skippedRecords += result.skippedRecords
        }

        return ParsedFileResult(events: events, sessions: sessions, diagnostics: diagnostics, skippedRecords: skippedRecords)
    }

    private func parseSessionFile(data: Data, file: URL) -> ParsedFileResult {
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseArrayRecords(array, file: file)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messages = obj["messages"] as? [[String: Any]] {
            return parseArrayRecords(messages, file: file)
        }
        return ParsedFileResult(events: [], sessions: [], diagnostics: [ParserDiagnosticsFactory.error(source: sourceID, filePath: file.path, message: "文件 schema 无法识别")], skippedRecords: 1)
    }

    private func parseArrayRecords(_ records: [[String: Any]], file: URL) -> ParsedFileResult {
        let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent.ifEmpty("unknown")
        var events: [UsageEvent] = []
        var diagnostics: [ParserDiagnostic] = []
        var skippedRecords = 0

        for (index, record) in records.enumerated() {
            guard let timestamp = DateParsing.parseISO8601(record["timestamp"] as? String)
                ?? DateParsing.parseISO8601(record["createdAt"] as? String) else {
                skippedRecords += 1
                diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 条记录缺少合法 timestamp"))
                continue
            }

            let model = record["model"] as? String ?? "gemini"
            let usage = record["usage"] as? [String: Any] ?? record["tokenUsage"] as? [String: Any]
            let input = usage?["inputTokens"] as? Int ?? usage?["input_tokens"] as? Int ?? 0
            let output = usage?["outputTokens"] as? Int ?? usage?["output_tokens"] as? Int ?? 0
            let cached = usage?["cachedTokens"] as? Int ?? 0
            let total = input + output
            guard total > 0 else {
                skippedRecords += 1
                diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 条记录无有效 token 信息"))
                continue
            }

            events.append(UsageEvent(
                id: StableID.make([sourceID, file.path, String(index), model, timestamp.ISO8601Format()]),
                source: sourceID,
                model: model,
                project: project,
                timestamp: timestamp,
                inputTokens: input,
                outputTokens: output,
                cachedTokens: cached,
                totalTokens: total
            ))
        }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let session = ParserSessionBuilder.buildSession(source: sourceID, model: sorted.last?.model ?? "gemini", project: project, filePath: file.path, events: sorted)
        return ParsedFileResult(events: sorted, sessions: session.map { [$0] } ?? [], diagnostics: diagnostics, skippedRecords: skippedRecords)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
