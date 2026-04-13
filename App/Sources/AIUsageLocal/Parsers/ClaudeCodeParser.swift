import Foundation

struct ClaudeCodeParser: UsageParser {
    let sourceID = "claude-code"
    let displayName = "Claude Code"

    func discoverCandidates() -> [URL] {
        ParserUtils.listFiles(recursive: ParserUtils.expandHome("~/.claude/projects"), suffixes: [".jsonl"])
    }

    func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var sessions: [SessionSummary] = []

        for file in files {
            guard let content = try? String(contentsOf: file) else { continue }
            let lines = content.split(separator: "\n")
            var sessionEvents: [UsageEvent] = []
            var model = "unknown"
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let timestamp = ParserUtils.isoDate(obj["timestamp"] as? String) ?? Date.distantPast
                let type = obj["type"] as? String ?? ""
                guard type == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                model = message["model"] as? String ?? model
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let cached = usage["cache_read_input_tokens"] as? Int ?? 0
                let total = input + output
                let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                let event = UsageEvent(
                    id: ParserUtils.hash(file.path + "-" + String(timestamp.timeIntervalSince1970)),
                    source: sourceID,
                    model: model,
                    project: project.isEmpty ? "unknown" : project,
                    timestamp: timestamp,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: cached,
                    totalTokens: total
                )
                events.append(event)
                sessionEvents.append(event)
            }

            if let first = sessionEvents.min(by: { $0.timestamp < $1.timestamp }),
               let last = sessionEvents.max(by: { $0.timestamp < $1.timestamp }) {
                sessions.append(SessionSummary(
                    id: ParserUtils.hash(file.path),
                    source: sourceID,
                    model: model,
                    project: first.project,
                    startedAt: first.timestamp,
                    endedAt: last.timestamp,
                    messages: sessionEvents.count,
                    totalTokens: sessionEvents.reduce(0) { $0 + $1.totalTokens },
                    filePath: file.path
                ))
            }
        }

        return ParsedFileResult(events: events, sessions: sessions)
    }
}
