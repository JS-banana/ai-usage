import Foundation

struct GeminiParser: UsageParser {
    let sourceID = "gemini"
    let displayName = "Gemini CLI"

    func discoverCandidates() -> [URL] {
        ParserUtils.listFiles(recursive: ParserUtils.expandHome("~/.gemini/tmp"), suffixes: [".json", ".jsonl"])
    }

    func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var sessions: [SessionSummary] = []

        for file in files where file.lastPathComponent.contains("session") || file.deletingLastPathComponent().path.contains("chats") {
            guard let data = try? Data(contentsOf: file) else { continue }
            let result = parseSessionFile(data: data, file: file)
            events.append(contentsOf: result.events)
            sessions.append(contentsOf: result.sessions)
        }

        return ParsedFileResult(events: events, sessions: sessions)
    }

    private func parseSessionFile(data: Data, file: URL) -> ParsedFileResult {
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseArrayRecords(array, file: file)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let messages = obj["messages"] as? [[String: Any]] {
            return parseArrayRecords(messages, file: file)
        }
        return ParsedFileResult(events: [], sessions: [])
    }

    private func parseArrayRecords(_ records: [[String: Any]], file: URL) -> ParsedFileResult {
        let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        var events: [UsageEvent] = []
        for record in records {
            let timestamp = ParserUtils.isoDate(record["timestamp"] as? String)
                ?? ParserUtils.isoDate(record["createdAt"] as? String)
                ?? Date.distantPast
            let model = record["model"] as? String ?? "gemini"
            let usage = record["usage"] as? [String: Any] ?? record["tokenUsage"] as? [String: Any]
            let input = usage?["inputTokens"] as? Int ?? usage?["input_tokens"] as? Int ?? 0
            let output = usage?["outputTokens"] as? Int ?? usage?["output_tokens"] as? Int ?? 0
            let cached = usage?["cachedTokens"] as? Int ?? 0
            let total = input + output
            guard total > 0 else { continue }
            events.append(UsageEvent(
                id: ParserUtils.hash(file.path + String(timestamp.timeIntervalSince1970)),
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

        let session = SessionSummary(
            id: ParserUtils.hash(file.path),
            source: sourceID,
            model: events.last?.model ?? "gemini",
            project: project,
            startedAt: events.first?.timestamp ?? .distantPast,
            endedAt: events.last?.timestamp ?? .distantPast,
            messages: events.count,
            totalTokens: events.reduce(0) { $0 + $1.totalTokens },
            filePath: file.path
        )
        return ParsedFileResult(events: events, sessions: events.isEmpty ? [] : [session])
    }
}
