import Foundation
import Domain
import Support

public struct OpenCodeParser: UsageParser {
    public let sourceID = "opencode"
    public let displayName = "OpenCode"

    public init() {}

    public func discoverCandidates() -> [URL] {
        FileDiscovery.listFiles(recursive: FileDiscovery.expandHome("~/.local/share/opencode/storage/message"), suffixes: [".json"])
    }

    public func parse(files: [URL]) -> ParsedFileResult {
        var events: [UsageEvent] = []
        var grouped: [String: [UsageEvent]] = [:]
        var diagnostics: [ParserDiagnostic] = []
        var skippedRecords = 0

        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                diagnostics.append(ParserDiagnosticsFactory.error(source: sourceID, filePath: file.path, message: "JSON 文件无法解析"))
                continue
            }

            guard let timestamp = DateParsing.parseISO8601((obj["time"] as? [String: Any])?["created"] as? String)
                ?? DateParsing.parseISO8601(obj["created_at"] as? String) else {
                skippedRecords += 1
                diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "缺少合法 timestamp"))
                continue
            }

            let model = obj["modelID"] as? String ?? obj["model"] as? String ?? "unknown"
            let rootPath = (obj["path"] as? [String: Any])?["root"] as? String ?? file.deletingLastPathComponent().lastPathComponent
            let project = URL(fileURLWithPath: rootPath).lastPathComponent.ifEmpty("unknown")
            let tokens = obj["tokens"] as? [String: Any]
            let input = tokens?["input"] as? Int ?? 0
            let output = tokens?["output"] as? Int ?? 0
            let cached = ((tokens?["cache"] as? [String: Any])?["read"] as? Int) ?? 0
            let total = input + output
            guard total > 0 else {
                skippedRecords += 1
                diagnostics.append(ParserDiagnosticsFactory.warning(source: sourceID, filePath: file.path, message: "记录无有效 token 信息"))
                continue
            }

            let sessionID = obj["sessionID"] as? String ?? file.deletingLastPathComponent().lastPathComponent
            let event = UsageEvent(
                id: StableID.make([sourceID, file.path, sessionID, timestamp.ISO8601Format()]),
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

        let sessions = grouped.compactMap { key, values in
            ParserSessionBuilder.buildSession(source: sourceID, model: values.last?.model ?? "unknown", project: values.last?.project ?? "unknown", filePath: key, events: values)
        }

        return ParsedFileResult(events: events, sessions: sessions, diagnostics: diagnostics, skippedRecords: skippedRecords)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
