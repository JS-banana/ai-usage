import XCTest
@testable import AiUsage

final class GroupQuotaReadModelTests: XCTestCase {
    func testGroupQuotaSnapshotBuildsTwoCompactWindows() {
        let service = GroupQuotaSummaryReadModelService()
        let now = Date(timeIntervalSince1970: 1_745_410_000)
        let payload = LaifuyouQuotaPayload(
            groupID: 2,
            groupName: "测试组",
            updatedAt: now,
            isStale: false,
            fiveHour: LaifuyouQuotaWindowPayload(
                id: "quota-5h",
                title: "5h",
                used: 1.5,
                limit: 5,
                remaining: 3.5,
                nextResetAt: now.addingTimeInterval(1800),
                progress: 0.3
            ),
            weekly: LaifuyouQuotaWindowPayload(
                id: "quota-7d",
                title: "周",
                used: 2,
                limit: 5,
                remaining: 3,
                nextResetAt: now.addingTimeInterval(86_400),
                progress: 0.4
            )
        )

        let snapshot = service.makeSnapshot(from: payload)

        XCTAssertEqual(snapshot.groupName, "测试组")
        XCTAssertEqual(snapshot.fiveHour.title, "5h")
        XCTAssertEqual(snapshot.weekly.title, "周")
        XCTAssertEqual(snapshot.fiveHour.primaryText, "已用 30%")
        XCTAssertEqual(snapshot.weekly.secondaryText, "2 / 5")
    }

    func testMenuBarSummaryUsesQuotaProgressForGlyph() {
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
        let summary = GroupQuotaSummarySnapshot(
            groupName: "测试组",
            updatedAt: Date(),
            status: .stale,
            message: "测试组 · 数据偏旧",
            fiveHour: .init(id: "5h", title: "5h", primaryText: "1 / 5", secondaryText: "剩余 4", footnoteText: "重置 soon", progress: 0.2),
            weekly: .init(id: "7d", title: "周", primaryText: "2 / 5", secondaryText: "剩余 3", footnoteText: "重置 later", progress: 0.4)
        )

        let snapshot = menuBar.makeSummary(overview: overview, groupQuotaSummary: summary)

        XCTAssertEqual(snapshot.status, .stale)
        XCTAssertEqual(snapshot.glyph.leftRatio, 0.2)
        XCTAssertEqual(snapshot.glyph.rightRatio, 0.4)
        XCTAssertFalse(snapshot.glyph.isDimmed)
    }
}
