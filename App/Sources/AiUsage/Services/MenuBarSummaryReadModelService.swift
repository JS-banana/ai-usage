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
        activeTargetID: String?,
        overview: OverviewPanelSnapshot?,
        entitlementsByTarget: [String: EntitlementSummarySnapshot]
    ) -> MenuBarSummarySnapshot {
        let targetID = activeTargetID ?? EntitlementTargetID.overview.storageKey
        guard let summary = entitlementsByTarget[targetID] else {
            return MenuBarSummarySnapshot(
                title: "AiUsage",
                subtitle: "暂无数据",
                status: .empty,
                glyph: .empty
            )
        }

        let subtitle = makeSubtitle(for: summary, targetID: targetID, overview: overview)
        let status: MenuBarSummarySnapshot.Status = summary.status == .stale ? .stale : (summary.status == .ready ? .ready : .empty)
        return MenuBarSummarySnapshot(
            title: "AiUsage",
            subtitle: subtitle,
            status: status,
            glyph: glyph(for: summary)
        )
    }

    private func makeSubtitle(
        for summary: EntitlementSummarySnapshot,
        targetID: String,
        overview: OverviewPanelSnapshot?
    ) -> String {
        if targetID == EntitlementTargetID.overview.storageKey {
            if summary.isDerived, let derivedFromTitle = summary.derivedFromTitle {
                return "总览 · 兜底 \(derivedFromTitle)"
            }
            switch summary.status {
            case .ready, .stale:
                return "总览 · \(summary.primaryWindow.primaryText)"
            case .failed:
                return "总览 · 刷新失败"
            case .configuredNonlive:
                return "总览 · 官方来源待接入"
            case .unconfigured:
                return overview == nil ? "总览 · 暂无数据" : "总览 · 未配置套餐来源"
            case .unavailable:
                return "总览 · 来源暂不可用"
            }
        }

        switch summary.status {
        case .ready, .stale:
            return "\(summary.title) · \(summary.primaryWindow.primaryText)"
        case .failed:
            return "\(summary.title) · 刷新失败"
        case .configuredNonlive:
            return "\(summary.title) · 官方来源待接入"
        case .unconfigured:
            return "\(summary.title) · 未配置套餐来源"
        case .unavailable:
            return "\(summary.title) · 来源暂不可用"
        }
    }

    private func glyph(for summary: EntitlementSummarySnapshot) -> QuotaMenuBarGlyphState {
        switch summary.status {
        case .ready, .stale:
            return QuotaMenuBarGlyphState(
                leftRatio: summary.primaryWindow.progress ?? 0.18,
                rightRatio: summary.secondaryWindow.progress ?? 0.18,
                isDimmed: false
            )
        case .failed, .configuredNonlive, .unconfigured, .unavailable:
            return .empty
        }
    }
}
