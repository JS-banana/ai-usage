import Foundation

enum QuotaMenuBarGlyphState: Hashable, Sendable {
    case dualWindows(leftRatio: Double, rightRatio: Double, isDimmed: Bool)
    case singlePlan(ratio: Double, isDimmed: Bool)
    case empty(kind: EmptyKind)

    enum EmptyKind: Hashable, Sendable {
        case dual
        case single
    }

    static let empty = QuotaMenuBarGlyphState.empty(kind: .dual)
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
            if summary.sourceKind == .mimo {
                let usedProgress = summary.menuBarProgress ?? summary.primaryWindow.progress
                return .singlePlan(ratio: remainingRatio(for: usedProgress), isDimmed: false)
            }
            return .dualWindows(
                leftRatio: remainingRatio(for: summary.primaryWindow.progress),
                rightRatio: remainingRatio(for: summary.secondaryWindow.progress),
                isDimmed: false
            )
        case .failed, .configuredNonlive, .unconfigured, .unavailable:
            return .empty(kind: summary.sourceKind == .mimo ? .single : .dual)
        }
    }

    private func remainingRatio(for usedProgress: Double?) -> Double {
        guard let usedProgress else { return 0.18 }
        return 1 - min(max(usedProgress, 0), 1)
    }
}
