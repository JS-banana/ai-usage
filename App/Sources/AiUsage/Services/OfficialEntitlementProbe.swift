import Foundation

actor OfficialEntitlementProbe {
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ data: Data) {
            lock.lock()
            storage.append(data)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            let copy = storage
            lock.unlock()
            return copy
        }
    }

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false

        func beginCompletion() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if completed { return false }
            completed = true
            return true
        }
    }

    func fetchSummary(for descriptor: EntitlementTargetDescriptor) async -> EntitlementSummarySnapshot {
        switch descriptor.targetID {
        case .provider(let providerID) where providerID == "codex":
            return await fetchCodexSummary(title: descriptor.name)
        case .provider(let providerID) where providerID == "claude-code":
            return await fetchClaudeSummary(title: descriptor.name)
        default:
            return EntitlementSummarySnapshot.placeholder(
                targetID: descriptor.targetID,
                title: descriptor.name,
                message: "该目标当前不支持官方套餐额度来源。",
                status: .unavailable,
                sourceKind: .official,
                primaryText: "不可用",
                secondaryText: "请改用第三方 API",
                footnote: "当前仅 Codex / Claude 尝试官方探测"
            )
        }
    }

    private func fetchCodexSummary(title: String) async -> EntitlementSummarySnapshot {
        let output = await runShell([
            "tmpdir=$(mktemp -d)",
            "cd \"$tmpdir\"",
            "{ sleep 1; printf '\\r/status\\r'; sleep 10; printf '\\r'; sleep 2; } | script -q /dev/null codex -s read-only -a untrusted"
        ].joined(separator: "; "), timeout: 18)
        let cleaned = stripANSICodes(output)
        let targetID: EntitlementTargetID = .provider("codex")

        if cleaned.contains("run codex login to use ChatGPT") || cleaned.contains("API key configured") {
            return EntitlementSummarySnapshot.placeholder(
                targetID: targetID,
                title: title,
                message: "已选择官方登录态，但当前 Codex CLI 未连接到 ChatGPT 套餐会话。",
                status: .configuredNonlive,
                sourceKind: .official,
                primaryText: "待登录",
                secondaryText: "运行 codex login 以使用 ChatGPT 套餐",
                footnote: "不会自动回退到第三方额度"
            )
        }

        let fiveLeft = firstPercent(inLineMatching: "5h limit", text: cleaned)
        let weeklyLeft = firstPercent(inLineMatching: "Weekly limit", text: cleaned)
        if let fiveLeft {
            let fiveUsed = max(0, min(100, 100 - fiveLeft))
            let weekUsed = weeklyLeft.map { max(0, min(100, 100 - $0)) }
            return EntitlementSummarySnapshot(
                targetID: targetID,
                title: title,
                message: "已从 Codex 官方 CLI 状态抓取套餐额度。",
                updatedAt: Date(),
                status: .ready,
                sourceKind: .official,
                provenance: .explicit,
                derivedFromTitle: nil,
                primaryWindow: .init(
                    id: "codex-official-5h",
                    title: "5h",
                    primaryText: "已用 \(fiveUsed)%",
                    secondaryText: "剩余 \(fiveLeft)%",
                    footnoteText: "重置时间待定",
                    progress: Double(fiveUsed) / 100.0
                ),
                secondaryWindow: .init(
                    id: "codex-official-7d",
                    title: "7d",
                    primaryText: weekUsed.map { "已用 \($0)%" } ?? "待定",
                    secondaryText: weeklyLeft.map { "剩余 \($0)%" } ?? "暂无周额度数据",
                    footnoteText: "重置时间待定",
                    progress: weekUsed.map { Double($0) / 100.0 }
                )
            )
        }

        return EntitlementSummarySnapshot.placeholder(
            targetID: targetID,
            title: title,
            message: "Codex 官方 CLI 已响应，但尚未返回可解析的套餐窗口。",
            status: .configuredNonlive,
            sourceKind: .official,
            primaryText: "待解析",
            secondaryText: "CLI 暂未给出可用额度数据",
            footnote: "如已登录，可稍后重试"
        )
    }

    private func fetchClaudeSummary(title: String) async -> EntitlementSummarySnapshot {
        let targetID: EntitlementTargetID = .provider("claude-code")
        let usageOutput = await runShell([
            "tmpdir=$(mktemp -d)",
            "cd \"$tmpdir\"",
            "{ sleep 1; printf '\\r/usage\\r'; sleep 14; printf '\\r'; sleep 2; } | script -q /dev/null claude"
        ].joined(separator: "; "), timeout: 24)
        let cleanedUsage = stripANSICodes(usageOutput)

        if let sessionLeft = firstPercent(inLineMatching: "Current session", text: cleanedUsage) {
            let weeklyLeft = firstPercent(inLineMatching: "Current week", text: cleanedUsage)
            let sessionUsed = max(0, min(100, 100 - sessionLeft))
            let weeklyUsed = weeklyLeft.map { max(0, min(100, 100 - $0)) }
            return EntitlementSummarySnapshot(
                targetID: targetID,
                title: title,
                message: "已从 Claude Code /usage 抓取套餐额度。",
                updatedAt: Date(),
                status: .ready,
                sourceKind: .official,
                provenance: .explicit,
                derivedFromTitle: nil,
                primaryWindow: .init(
                    id: "claude-official-5h",
                    title: "5h",
                    primaryText: "已用 \(sessionUsed)%",
                    secondaryText: "剩余 \(sessionLeft)%",
                    footnoteText: "重置时间待定",
                    progress: Double(sessionUsed) / 100.0
                ),
                secondaryWindow: .init(
                    id: "claude-official-7d",
                    title: "7d",
                    primaryText: weeklyUsed.map { "已用 \($0)%" } ?? "待定",
                    secondaryText: weeklyLeft.map { "剩余 \($0)%" } ?? "暂无周额度数据",
                    footnoteText: "重置时间待定",
                    progress: weeklyUsed.map { Double($0) / 100.0 }
                )
            )
        }

        let printOutput = await runShell("tmpdir=$(mktemp -d); cd \"$tmpdir\"; claude -p '/usage'", timeout: 12)
        let cleanedPrint = stripANSICodes(printOutput)
        if cleanedPrint.localizedCaseInsensitiveContains("subscription") {
            return EntitlementSummarySnapshot.placeholder(
                targetID: targetID,
                title: title,
                message: "已检测到 Claude Code 订阅，但当前命令输出未返回实时额度窗口。",
                status: .configuredNonlive,
                sourceKind: .official,
                primaryText: "已订阅",
                secondaryText: "官方 CLI 未暴露数值额度",
                footnote: "不会自动回退到第三方额度"
            )
        }

        return EntitlementSummarySnapshot.placeholder(
            targetID: targetID,
            title: title,
            message: "Claude 官方套餐额度暂未能从本机登录态解析。",
            status: .configuredNonlive,
            sourceKind: .official,
            primaryText: "待接入",
            secondaryText: "CLI 当前未返回可解析额度",
            footnote: "如已登录，可稍后重试"
        )
    }

    private func runShell(_ script: String, timeout: TimeInterval) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let buffer = OutputBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty == false { buffer.append(chunk) }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty == false { buffer.append(chunk) }
            }

            let gate = CompletionGate()
            let finish: @Sendable () -> Void = {
                if gate.beginCompletion() == false {
                    return
                }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
                let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
                if remainingOut.isEmpty == false { buffer.append(remainingOut) }
                let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()
                if remainingErr.isEmpty == false { buffer.append(remainingErr) }
                continuation.resume(returning: String(decoding: buffer.snapshot(), as: UTF8.self))
            }

            process.terminationHandler = { _ in finish() }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: error.localizedDescription)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish()
            }
        }
    }

    private func firstPercent(inLineMatching marker: String, text: String) -> Int? {
        text.split(separator: "\n").first(where: { $0.localizedCaseInsensitiveContains(marker) }).flatMap { line in
            let pattern = #"([0-9]{1,3})%"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let source = String(line)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            guard let match = regex.firstMatch(in: source, range: range),
                  let valueRange = Range(match.range(at: 1), in: source)
            else {
                return nil
            }
            return Int(source[valueRange])
        }
    }

    private func stripANSICodes(_ text: String) -> String {
        let patterns = [#"\u001B\[[0-9;?]*[ -/]*[@-~]"#, #"\u001B\][^\u0007]*(\u0007|\u001B\\)"#, #"\r"#]
        return patterns.reduce(text) { partial, pattern in
            partial.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
    }
}
