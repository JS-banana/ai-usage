import XCTest
import AppKit
import Support
@testable import AiUsage

final class MenuBarShapeTests: XCTestCase {
    func testFullNumberFormattingDoesNotAbbreviatePrimaryValue() {
        let value = CompactNumberFormatting.fullString(71_243_790)
        XCTAssertFalse(value.contains("亿"))
        XCTAssertFalse(value.contains("万"))
        XCTAssertFalse(value.contains("百万"))
    }

    func testApproximateYiNoteAppearsOnlyForLargeValues() {
        XCTAssertEqual(CompactNumberFormatting.approximateInYi(71_243_790), "约 0.71 亿")
        XCTAssertNil(CompactNumberFormatting.approximateInYi(5_000_000))
    }

    func testRenderedMenuBarImageIsTemplateAndSizedForStatusBar() {
        let image = QuotaMenuBarImageRenderer().image(
            for: QuotaMenuBarGlyphState(leftRatio: 0.25, rightRatio: 0.6, isDimmed: false)
        )

        XCTAssertEqual(image.size.width, 18)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertTrue(image.isTemplate)
    }

    func testRootViewSourceShowsActiveEntitlementAndCompactActions() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/RootView.swift")
        XCTAssertTrue(source.contains("displayedEntitlementSummary"))
        XCTAssertTrue(source.contains("entitlementSummaryCard(activeEntitlementSummary)"))
        XCTAssertTrue(source.contains("summary.status != .unconfigured"))
        XCTAssertTrue(source.contains("actionToolbar"))
        XCTAssertTrue(source.contains("CompactActionButton"))
        XCTAssertTrue(source.contains("管理账号"))
        XCTAssertTrue(source.contains("关于 AiUsage"))
        XCTAssertTrue(source.contains("退出"))
        XCTAssertTrue(source.contains(".help(title)"))
        XCTAssertTrue(source.contains(".onHover"))
        XCTAssertTrue(source.contains("if isHovered"))
        XCTAssertTrue(source.contains(".fixedSize()"))
        XCTAssertTrue(source.contains("ProviderTabButton(tab: tab"))
        XCTAssertTrue(source.contains("ProviderTabMiniProgress"))
        XCTAssertFalse(source.contains("actionList"))
        XCTAssertFalse(source.contains("ActionRow"))
        XCTAssertFalse(source.contains("appState.groupQuotaSummary"))
        XCTAssertFalse(source.contains("ellipsis.circle"))
        XCTAssertFalse(source.contains("font(.caption.weight(.medium))"))
    }

    func testAppShellUsesRenderedTemplateImageForMenuBarExtra() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/AiUsageApp.swift")
        XCTAssertTrue(source.contains("QuotaMenuBarImageRenderer"))
        XCTAssertTrue(source.contains("Image(nsImage:"))
        XCTAssertFalse(source.contains("chart.bar.xaxis"))
    }

    func testSettingsSourceIncludesTargetScopedEntitlementSections() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/SettingsView.swift")
        XCTAssertTrue(source.contains("账号与来源"))
        XCTAssertTrue(source.contains("EntitlementPreferences.descriptorTargets"))
        XCTAssertTrue(source.contains("Picker(\"来源\""))
        XCTAssertTrue(source.contains("总览套餐额度"))
        XCTAssertTrue(source.contains("Quota URL"))
        XCTAssertFalse(source.contains("Quota 服务"))
        XCTAssertFalse(source.contains("Group ID"))
    }

    func testQuotaSummarySourceKeepsTwoWindowCompactCards() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/QuotaSummaryViews.swift")
        XCTAssertTrue(source.contains("QuotaProgressRiskLevel"))
        XCTAssertTrue(source.contains("CompactQuotaWindowCard(window: summary.primaryWindow"))
        XCTAssertTrue(source.contains("CompactQuotaWindowCard(window: summary.secondaryWindow"))
        XCTAssertFalse(source.contains("summary.fiveHour"))
        XCTAssertFalse(source.contains("summary.weekly"))
        XCTAssertFalse(source.contains("Text(summary.title)"))
        XCTAssertFalse(source.contains("window.secondaryText"))
    }

    func testBrandCatalogSourceProvidesKnownProviderMappings() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Models/ProviderBrandCatalog.swift")
        XCTAssertTrue(source.contains("case \"claude-code\""))
        XCTAssertTrue(source.contains("case \"codex\""))
        XCTAssertTrue(source.contains("case \"opencode\""))
        XCTAssertTrue(source.contains("case \"gemini\""))
        XCTAssertTrue(source.contains("case \"antigravity\""))
        XCTAssertTrue(source.contains("case \"overview\""))
    }

    func testProviderDetailViewShowsActiveEntitlementCard() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/ProviderDetailView.swift")
        XCTAssertTrue(source.contains("displayedEntitlementSummary"))
        XCTAssertTrue(source.contains("PanelDetailCard(title: \"套餐额度\")"))
        XCTAssertTrue(source.contains("summary.status != .unconfigured"))
        XCTAssertFalse(source.contains("appState.groupQuotaSummary"))
    }

    private func sourceText(path: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path))
    }
}
