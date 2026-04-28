import Foundation

struct QuotaMenuBarGlyphState: Hashable, Sendable {
    let leftRatio: Double
    let rightRatio: Double
    let isDimmed: Bool

    static let empty = QuotaMenuBarGlyphState(leftRatio: 0.18, rightRatio: 0.18, isDimmed: true)
}

struct MenuBarSummarySnapshot: Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case ready
        case stale
        case empty
    }

    let title: String
    let subtitle: String
    let status: Status
    let glyph: QuotaMenuBarGlyphState
}

struct MenuBarSummaryReadModelService {
    func makeSummary(
        overview: OverviewPanelSnapshot?,
        groupQuotaSummary: GroupQuotaSummarySnapshot
    ) -> MenuBarSummarySnapshot {
        guard let overview else {
            return MenuBarSummarySnapshot(
                title: "AiUsage",
                subtitle: "暂无数据",
                status: .empty,
                glyph: glyph(for: groupQuotaSummary)
            )
        }

        let status: MenuBarSummarySnapshot.Status
        switch groupQuotaSummary.status {
        case .stale:
            status = .stale
        case .ready, .failed, .unconfigured:
            status = .ready
        }

        return MenuBarSummarySnapshot(
            title: "AiUsage",
            subtitle: "请求 \(overview.todayRequests.formatted()) · Tokens \(overview.todayTokens.formatted())",
            status: status,
            glyph: glyph(for: groupQuotaSummary)
        )
    }

    private func glyph(for summary: GroupQuotaSummarySnapshot) -> QuotaMenuBarGlyphState {
        switch summary.status {
        case .ready, .stale:
            return QuotaMenuBarGlyphState(
                leftRatio: summary.fiveHour.progress ?? 0.18,
                rightRatio: summary.weekly.progress ?? 0.18,
                isDimmed: false
            )
        case .unconfigured, .failed:
            return .empty
        }
    }
}
