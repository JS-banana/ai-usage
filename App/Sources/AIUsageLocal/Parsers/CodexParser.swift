import Foundation

struct CodexParser: UsageParser {
    let sourceID = "codex"
    let displayName = "Codex CLI"

    func discoverCandidates() -> [URL] {
        ParserUtils.listFiles(recursive: ParserUtils.expandHome("~/.codex/sessions"), suffixes: [".jsonl"])
    }

    func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var sessions: [SessionSummary] = []

        for file in files {
            guard let content = try? String(contentsOf: file) else { continue }
            let lines = content.split(separator: "\n")
            var collected: [UsageEvent] = []
            var currentModel = "unknown"
            var currentProject = file.deletingLastPathComponent().lastPathComponent
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let timestamp = ParserUtils.isoDate(obj["timestamp"] as? String) ?? ParserUtils.isoDate(obj["created_at"] as? String) ?? Date.distantPast
                if let model = obj["model"] as? String { currentModel = model }
                if let cwd = obj["cwd"] as? String { currentProject = URL(fileURLWithPath: cwd).lastPathComponent }
                let usage = obj["usage"] as? [String: Any] ?? obj["token_usage"] as? [String: Any]
                guard let usage else { continue }
                let input = usage["input_tokens"] as? Int ?? usage["input"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? usage["output"] as? Int ?? 0
                let cached = usage["cached_input_tokens"] as? Int ?? usage["cache_read_input_tokens"] as? Int ?? 0
                let total = input + output
                let event = UsageEvent(
                    id: ParserUtils.hash(file.path + String(timestamp.timeIntervalSince1970) + currentModel),
                    source: sourceID,
                    model: currentModel,
                    project: currentProject,
                    timestamp: timestamp,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: cached,
                    totalTokens: total
                )
                events.append(event)
                collected.append(event)
            }
            if let first = collected.min(by: { $0.timestamp < $1.timestamp }),
               let last = collected.max(by: { $0.timestamp < $1.timestamp }) {
                sessions.append(SessionSummary(
                    id: ParserUtils.hash(file.path),
                    source: sourceID,
                    model: currentModel,
                    project: currentProject,
                    startedAt: first.timestamp,
                    endedAt: last.timestamp,
                    messages: collected.count,
                    totalTokens: collected.reduce(0) { $0 + $1.totalTokens },
                    filePath: file.path
                ))
            }
        }

        return ParsedFileResult(events: events, sessions: sessions)
    }
}
