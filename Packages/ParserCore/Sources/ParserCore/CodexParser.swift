import Foundation
import Domain
import Support

public struct CodexParser: UsageParser {
    public let sourceID = "codex"
    public let displayName = "Codex CLI"

    public init() {}

    public func discoverCandidates() -> [URL] {
        FileDiscovery.listFiles(recursive: FileDiscovery.expandHome("~/.codex/sessions"), suffixes: [".jsonl"])
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

            var fileEvents: [UsageEvent] = []
            var currentModel = "unknown"
            var currentProject = file.deletingLastPathComponent().lastPathComponent.ifEmpty("unknown")

            for (index, line) in content.split(separator: "\n").enumerated() {
                guard let data = String(line).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedRecords += 1
                    diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 行 JSON 无法解析"))
                    continue
                }

                if let sessionMeta = obj["payload"] as? [String: Any], (obj["type"] as? String) == "session_meta" {
                    if let payloadModel = sessionMeta["model"] as? String, payloadModel.isEmpty == false {
                        currentModel = payloadModel
                    }
                    if let provider = sessionMeta["model_provider"] as? String,
                       currentModel == "unknown",
                       provider.isEmpty == false {
                        currentModel = provider
                    }
                    if let cwd = sessionMeta["cwd"] as? String, cwd.isEmpty == false {
                        currentProject = URL(fileURLWithPath: cwd).lastPathComponent.ifEmpty("unknown")
                    }
                }

                if let turnContext = obj["payload"] as? [String: Any], (obj["type"] as? String) == "turn_context" {
                    if let model = turnContext["model"] as? String, model.isEmpty == false {
                        currentModel = model
                    }
                    if let cwd = turnContext["cwd"] as? String, cwd.isEmpty == false {
                        currentProject = URL(fileURLWithPath: cwd).lastPathComponent.ifEmpty("unknown")
                    }
                }

                if let model = obj["model"] as? String, model.isEmpty == false { currentModel = model }
                if let cwd = obj["cwd"] as? String, cwd.isEmpty == false { currentProject = URL(fileURLWithPath: cwd).lastPathComponent }

                guard let usage = usagePayload(from: obj) else {
                    continue
                }

                guard let timestamp = DateParsing.parseISO8601(obj["timestamp"] as? String) ?? DateParsing.parseISO8601(obj["created_at"] as? String) else {
                    skippedRecords += 1
                    diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 行 usage 记录缺少合法 timestamp"))
                    continue
                }

                let input = usage["input_tokens"] as? Int ?? usage["input"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? usage["output"] as? Int ?? 0
                let cached = usage["cached_input_tokens"] as? Int ?? usage["cache_read_input_tokens"] as? Int ?? 0
                let total = usage["total_tokens"] as? Int ?? (input + output + cached)

                guard total > 0 else {
                    skippedRecords += 1
                    diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "第 \(index + 1) 行 usage 记录无有效 token 信息"))
                    continue
                }

                let event = UsageEvent(
                    id: StableID.make([sourceID, file.path, String(index), currentModel, timestamp.ISO8601Format()]),
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
                fileEvents.append(event)
            }

            if let session = ParserSessionBuilder.buildSession(source: sourceID, model: currentModel, project: currentProject, filePath: file.path, events: fileEvents) {
                sessions.append(session)
            }
        }

        return ParsedFileResult(events: events, sessions: sessions, diagnostics: diagnostics, skippedRecords: skippedRecords)
    }

    private func usagePayload(from obj: [String: Any]) -> [String: Any]? {
        if let usage = obj["usage"] as? [String: Any] ?? obj["token_usage"] as? [String: Any] {
            return usage
        }

        guard let type = obj["type"] as? String, type == "event_msg",
              let payload = obj["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "token_count",
              let info = payload["info"] as? [String: Any] else {
            return nil
        }

        if let last = info["last_token_usage"] as? [String: Any] {
            return last
        }
        if let total = info["total_token_usage"] as? [String: Any] {
            return total
        }
        return nil
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
