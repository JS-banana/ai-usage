import XCTest
@testable import AiUsage

final class EntitlementReadModelTests: XCTestCase {
    func testMenuBarSummaryUsesActiveTargetProgressForGlyph() {
        let menuBar = MenuBarSummaryReadModelService()
        let overview = OverviewPanelSnapshot(
            todayTokens: 1200,
            sevenDayTokens: 4800,
            todayRequests: 6,
            sevenDayRequests: 24,
            cachedTokens: 100,
            activeSources: 2,
            trendPoints: [],
            providerRows: [],
            lastRefresh: Date()
        )
        let summary = EntitlementSummarySnapshot(
            targetID: .provider("codex"),
            title: "Codex",
            message: "第三方套餐额度数据偏旧。",
            updatedAt: Date(),
            status: .stale,
            sourceKind: .thirdParty,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(id: "5h", title: "5h", primaryText: "已用 20%", secondaryText: "1 / 5", footnoteText: "重置 soon", progress: 0.2),
            secondaryWindow: .init(id: "7d", title: "7d", primaryText: "已用 40%", secondaryText: "2 / 5", footnoteText: "重置 later", progress: 0.4)
        )

        let snapshot = menuBar.makeSummary(
            activeTargetID: "codex",
            overview: overview,
            entitlementsByTarget: ["codex": summary]
        )

        XCTAssertEqual(snapshot.status, .stale)
        XCTAssertEqual(snapshot.glyph.leftRatio, 0.2)
        XCTAssertEqual(snapshot.glyph.rightRatio, 0.4)
        XCTAssertFalse(snapshot.glyph.isDimmed)
        XCTAssertTrue(snapshot.subtitle.contains("Codex"))
    }

    func testDerivedOverviewSummaryUsesFallbackSubtitle() {
        let menuBar = MenuBarSummaryReadModelService()
        let snapshot = menuBar.makeSummary(
            activeTargetID: EntitlementTargetID.overview.storageKey,
            overview: nil,
            entitlementsByTarget: [
                EntitlementTargetID.overview.storageKey: EntitlementSummarySnapshot(
                    targetID: .overview,
                    title: "总览套餐",
                    message: "未配置总览来源，当前显示风险最高的 provider 额度摘要。",
                    updatedAt: Date(),
                    status: .ready,
                    sourceKind: .thirdParty,
                    provenance: .derived,
                    derivedFromTitle: "Codex",
                    primaryWindow: .init(id: "5h", title: "5h", primaryText: "已用 55%", secondaryText: "11 / 20", footnoteText: "重置 soon", progress: 0.55),
                    secondaryWindow: .init(id: "7d", title: "7d", primaryText: "已用 65%", secondaryText: "13 / 20", footnoteText: "重置 later", progress: 0.65)
                )
            ]
        )

        XCTAssertTrue(snapshot.subtitle.contains("兜底 Codex"))
    }

    func testQuotaRiskLevelThresholdsMatchPopupSpec() {
        XCTAssertEqual(QuotaProgressRiskLevel.forProgress(0.10), .green)
        XCTAssertEqual(QuotaProgressRiskLevel.forProgress(0.35), .yellow)
        XCTAssertEqual(QuotaProgressRiskLevel.forProgress(0.60), .orange)
        XCTAssertEqual(QuotaProgressRiskLevel.forProgress(0.80), .red)
    }
}
