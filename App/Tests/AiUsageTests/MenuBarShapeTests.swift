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

    func testRootViewSourceShowsCompactManagementEntry() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/RootView.swift")
        XCTAssertTrue(source.contains("actionList"))
        XCTAssertTrue(source.contains("添加 / 管理账号"))
        XCTAssertTrue(source.contains("关于 AiUsage"))
        XCTAssertTrue(source.contains("TrendContent(title: \"近 7 天\""))
        XCTAssertTrue(source.contains("selectedTabID == \"overview\""))
        XCTAssertTrue(source.contains("onContinuousHover"))
        XCTAssertFalse(source.contains("accountSummaries"))
    }

    func testAppShellUsesRenderedTemplateImageForMenuBarExtra() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/AiUsageApp.swift")
        XCTAssertTrue(source.contains("QuotaMenuBarImageRenderer"))
        XCTAssertTrue(source.contains("Image(nsImage:"))
        XCTAssertFalse(source.contains("chart.bar.xaxis"))
    }

    func testSettingsSourceIncludesProviderVisibilityToggles() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/SettingsView.swift")
        XCTAssertTrue(source.contains("账号与来源"))
        XCTAssertTrue(source.contains("Toggle("))
        XCTAssertTrue(source.contains("你可以决定展示哪些 agent / account 的 usage 统计"))
        XCTAssertTrue(source.contains("Quota URL"))
        XCTAssertTrue(source.contains("Quota 总额度预览"))
        XCTAssertFalse(source.contains("Group ID"))
        XCTAssertFalse(source.contains("ForEach(appState.accountSummaries)"))
    }

    func testReadModelServiceDoesNotHardcodeProviderNameSwitches() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Services/AppReadModelService.swift")
        XCTAssertTrue(source.contains("providerDescriptors()"))
        XCTAssertFalse(source.contains("shortProviderName"))
        XCTAssertFalse(source.contains("switch descriptor.id"))
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
