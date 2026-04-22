import Foundation
import Domain
import Support

public struct ClaudeCodeParser: UsageParser {
    public let sourceID = "claude-code"
    public let displayName = "Claude Code"

    public init() {}

    public func discoverCandidates() -> [URL] {
        FileDiscovery.listFiles(recursive: FileDiscovery.expandHome("~/.claude/projects"), suffixes: [".jsonl"])
            .filter { $0.path.contains("claude-mem-observer-sessions") == false }
    }

    public func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var sessions: [SessionSummary] = []
        var diagnostics: [ParserDiagnostic] = []
        var skippedRecords = 0

        for file in files {
            guard let content = try? String(contentsOf: file) else {
                diagnostics.append(ParserDiagnosticsFactory.error(source: sourceID, filePath: file.path, message: "无法读取文件"))
                continue
            }

            var sessionEvents: [UsageEvent] = []
            var lastModel = "unknown"
            let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent.ifEmpty("unknown")

            for (index, line) in content.split(separator: "\n").enumerated() {
                guard let data = String(line).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedRecords += 1
                    diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 行 JSON 无法解析"))
                    continue
                }

                guard let timestamp = DateParsing.parseISO8601(obj["timestamp"] as? String) else {
                    skippedRecords += 1
                    diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 行缺少合法 timestamp"))
                    continue
                }

                let type = obj["type"] as? String ?? ""
                guard type == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    continue
                }

                lastModel = message["model"] as? String ?? lastModel
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let cached = usage["cache_read_input_tokens"] as? Int ?? 0
                let total = input + output + cached

                guard lastModel != "<synthetic>", total > 0 else {
                    continue
                }

                let event = UsageEvent(
                    id: StableID.make([sourceID, file.path, String(index), lastModel, timestamp.ISO8601Format()]),
                    source: sourceID,
                    model: lastModel,
                    project: project,
                    timestamp: timestamp,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: cached,
                    totalTokens: total
                )
                events.append(event)
                sessionEvents.append(event)
            }

            if let session = ParserSessionBuilder.buildSession(source: sourceID, model: lastModel, project: project, filePath: file.path, events: sessionEvents) {
                sessions.append(session)
            }
        }

        return ParsedFileResult(events: events, sessions: sessions, diagnostics: diagnostics, skippedRecords: skippedRecords)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
