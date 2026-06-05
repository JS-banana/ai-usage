import XCTest
@testable import AiUsage

final class MenuBarQuotaTargetTests: XCTestCase {
    func testAutoTargetChoosesLowestRemainingReadyOrStaleSummary() {
        let service = MenuBarSummaryReadModelService()
        let summary = service.makeSummary(
            targetPreference: .auto,
            overview: nil,
            entitlementsByTarget: [
                "mimo": quotaSummary(id: "mimo", title: "MiMo", sourceKind: .mimo, progress: 0.2),
                "openai": quotaSummary(id: "openai", title: "GPT Plus", sourceKind: .thirdParty, progress: 0.82)
            ]
        )

        XCTAssertEqual(summary.subtitle, "GPT Plus · 82% used")
        guard case .dualWindows(let leftRatio, _, _) = summary.glyph else {
            return XCTFail("Expected GPT Plus dual-window glyph")
        }
        XCTAssertEqual(leftRatio, 0.18, accuracy: 0.001)
    }

    func testExplicitTargetPinsMenuBarToSelectedSummary() {
        let service = MenuBarSummaryReadModelService()
        let summary = service.makeSummary(
            targetPreference: .target("mimo"),
            overview: nil,
            entitlementsByTarget: [
                "mimo": quotaSummary(id: "mimo", title: "MiMo", sourceKind: .mimo, progress: 0.2),
                "openai": quotaSummary(id: "openai", title: "GPT Plus", sourceKind: .thirdParty, progress: 0.82)
            ]
        )

        XCTAssertEqual(summary.subtitle, "MiMo · 20% used")
        guard case .singlePlan(let ratio, _) = summary.glyph else {
            return XCTFail("Expected pinned MiMo single-plan glyph")
        }
        XCTAssertEqual(ratio, 0.8, accuracy: 0.001)
    }

    func testMissingExplicitTargetReturnsEmptyInsteadOfSwitchingTargets() {
        let service = MenuBarSummaryReadModelService()
        let summary = service.makeSummary(
            targetPreference: .target("missing"),
            overview: nil,
            entitlementsByTarget: [
                "openai": quotaSummary(id: "openai", title: "GPT Plus", sourceKind: .thirdParty, progress: 0.82)
            ]
        )

        XCTAssertEqual(summary.status, .empty)
        XCTAssertEqual(summary.subtitle, "missing · 暂无额度数据")
        XCTAssertEqual(summary.glyph, .empty)
    }

    func testMenuBarTargetPreferencePersists() {
        let defaults = UserDefaults(suiteName: "MenuBarQuotaTargetTests")!
        defaults.removePersistentDomain(forName: "MenuBarQuotaTargetTests")

        XCTAssertEqual(EntitlementPreferences.menuBarTargetPreference(userDefaults: defaults), .auto)

        EntitlementPreferences.setMenuBarTargetPreference(.target("mimo"), userDefaults: defaults)

        XCTAssertEqual(EntitlementPreferences.menuBarTargetPreference(userDefaults: defaults), .target("mimo"))

        EntitlementPreferences.setMenuBarTargetPreference(.auto, userDefaults: defaults)

        XCTAssertEqual(EntitlementPreferences.menuBarTargetPreference(userDefaults: defaults), .auto)
    }

    private func quotaSummary(
        id: String,
        title: String,
        sourceKind: EntitlementSourceKind,
        progress: Double
    ) -> EntitlementSummarySnapshot {
        EntitlementSummarySnapshot(
            targetID: .provider(id),
            title: title,
            message: "",
            updatedAt: Date(),
            status: .ready,
            sourceKind: sourceKind,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: .init(
                id: "\(id)-primary",
                title: "5h",
                primaryText: "\(Int(progress * 100))% used",
                secondaryText: "",
                footnoteText: "",
                progress: progress
            ),
            secondaryWindow: .init(
                id: "\(id)-secondary",
                title: "7d",
                primaryText: "\(Int(progress * 100))% used",
                secondaryText: "",
                footnoteText: "",
                progress: progress
            ),
            menuBarProgress: progress
        )
    }
}
