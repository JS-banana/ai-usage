import Foundation

struct OpenCodeParser: UsageParser {
    let sourceID = "opencode"
    let displayName = "OpenCode"

    func discoverCandidates() -> [URL] {
        let root = ParserUtils.expandHome("~/.local/share/opencode/storage/message")
        return ParserUtils.listFiles(recursive: root, suffixes: [".json"])
    }

    func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var grouped: [String: [UsageEvent]] = [:]

        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let timestamp = ParserUtils.isoDate((obj["time"] as? [String: Any])?["created"] as? String)
                ?? ParserUtils.isoDate(obj["created_at"] as? String)
                ?? Date.distantPast
            let model = obj["modelID"] as? String ?? obj["model"] as? String ?? "unknown"
            let rootPath = (obj["path"] as? [String: Any])?["root"] as? String ?? file.deletingLastPathComponent().lastPathComponent
            let project = URL(fileURLWithPath: rootPath).lastPathComponent
            let tokens = obj["tokens"] as? [String: Any]
            let input = tokens?["input"] as? Int ?? 0
            let output = tokens?["output"] as? Int ?? 0
            let cached = ((tokens?["cache"] as? [String: Any])?["read"] as? Int) ?? 0
            let total = input + output
            guard total > 0 else { continue }
            let sessionID = obj["sessionID"] as? String ?? file.deletingLastPathComponent().lastPathComponent
            let event = UsageEvent(
                id: ParserUtils.hash(file.path),
                source: sourceID,
                model: model,
                project: project,
                timestamp: timestamp,
                inputTokens: input,
                outputTokens: output,
                cachedTokens: cached,
                totalTokens: total
            )
            events.append(event)
            grouped[sessionID, default: []].append(event)
        }

        let sessions = grouped.map { key, values in
            let sorted = values.sorted { $0.timestamp < $1.timestamp }
            return SessionSummary(
                id: ParserUtils.hash(key),
                source: sourceID,
                model: sorted.last?.model ?? "unknown",
                project: sorted.last?.project ?? "unknown",
                startedAt: sorted.first?.timestamp ?? .distantPast,
                endedAt: sorted.last?.timestamp ?? .distantPast,
                messages: sorted.count,
                totalTokens: sorted.reduce(0) { $0 + $1.totalTokens },
                filePath: key
            )
        }

        return ParsedFileResult(events: events, sessions: sessions)
    }
}
