import Foundation

struct GroupQuotaWindowSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let primaryText: String
    let secondaryText: String
    let footnoteText: String
    let progress: Double?
}

enum GroupQuotaSummaryStatus: String, Hashable, Sendable {
    case ready
    case stale
    case unconfigured
    case failed
}

struct GroupQuotaSummarySnapshot: Hashable, Sendable {
    let groupName: String
    let updatedAt: Date?
    let status: GroupQuotaSummaryStatus
    let message: String
    let fiveHour: GroupQuotaWindowSnapshot
    let weekly: GroupQuotaWindowSnapshot

    static func unconfigured() -> GroupQuotaSummarySnapshot {
        GroupQuotaSummaryReadModelService().makeUnconfiguredSnapshot()
    }
}

struct GroupQuotaSummaryReadModelService {
    func makeSnapshot(from payload: LaifuyouQuotaPayload) -> GroupQuotaSummarySnapshot {
        let status: GroupQuotaSummaryStatus = payload.isStale ? .stale : .ready
        let message = payload.isStale ? "\(payload.groupName) · 数据偏旧" : "\(payload.groupName) · 已更新"
        return GroupQuotaSummarySnapshot(
            groupName: payload.groupName,
            updatedAt: payload.updatedAt,
            status: status,
            message: message,
            fiveHour: makeWindowSnapshot(payload.fiveHour),
            weekly: makeWindowSnapshot(payload.weekly)
        )
    }

    func makeUnconfiguredSnapshot() -> GroupQuotaSummarySnapshot {
        GroupQuotaSummarySnapshot(
            groupName: "分组总额度",
            updatedAt: nil,
            status: .unconfigured,
            message: "在设置中填写 Quota URL 与 API Key 后启用",
            fiveHour: placeholderWindow(
                id: "quota-5h-unconfigured",
                title: "5h",
                primary: "未配置",
                secondary: "填写 API Key",
                footnote: "仅保存在本机设置"
            ),
            weekly: placeholderWindow(
                id: "quota-7d-unconfigured",
                title: "周",
                primary: "未配置",
                secondary: "填写 Quota URL",
                footnote: "客户端不展示账号拆分"
            )
        )
    }

    func makeFailureSnapshot(error: any Error) -> GroupQuotaSummarySnapshot {
        let detail = sanitizedError(error)
        return GroupQuotaSummarySnapshot(
            groupName: "分组总额度",
            updatedAt: nil,
            status: .failed,
            message: "Quota 刷新失败，但 usage 已保留",
            fiveHour: placeholderWindow(
                id: "quota-5h-failed",
                title: "5h",
                primary: "刷新失败",
                secondary: detail,
                footnote: "Usage facts 未受影响"
            ),
            weekly: placeholderWindow(
                id: "quota-7d-failed",
                title: "周",
                primary: "刷新失败",
                secondary: detail,
                footnote: "可稍后重试"
            )
        )
    }

    private func makeWindowSnapshot(_ window: LaifuyouQuotaWindowPayload) -> GroupQuotaWindowSnapshot {
        GroupQuotaWindowSnapshot(
            id: window.id,
            title: window.title,
            primaryText: percentageText(window.progress),
            secondaryText: usageText(used: window.used, limit: window.limit),
            footnoteText: resetText(window.nextResetAt),
            progress: window.progress
        )
    }

    private func placeholderWindow(
        id: String,
        title: String,
        primary: String,
        secondary: String,
        footnote: String
    ) -> GroupQuotaWindowSnapshot {
        GroupQuotaWindowSnapshot(
            id: id,
            title: title,
            primaryText: primary,
            secondaryText: secondary,
            footnoteText: footnote,
            progress: nil
        )
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "重置时间待定" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return "重置 \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func format(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return Int(value.rounded()).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func percentageText(_ progress: Double?) -> String {
        guard let progress else { return "已用 —" }
        let clamped = min(max(progress, 0), 1)
        return "已用 \(clamped.formatted(.percent.precision(.fractionLength(0))))"
    }

    private func usageText(used: Double, limit: Double?) -> String {
        guard let limit else { return "已用 \(format(used))" }
        return "\(format(used)) / \(format(limit))"
    }

    private func sanitizedError(_ error: any Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "未知错误" : raw
    }
}
