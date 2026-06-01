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
        XCTAssertTrue(source.contains("ActionListRow"))
        XCTAssertTrue(source.contains("添加账号"))
        XCTAssertTrue(source.contains("completedMiMoLoginSequence"))
        XCTAssertTrue(source.contains("showInlineLogin = false"))
        XCTAssertTrue(source.contains("关于 AiUsage"))
        XCTAssertTrue(source.contains("退出"))
        XCTAssertTrue(source.contains(".onHover"))
        XCTAssertTrue(source.contains("isHovered"))
        XCTAssertTrue(source.contains("ProviderTabButton(tab: tab"))
        XCTAssertTrue(source.contains("ProviderTabMiniProgress"))
        XCTAssertFalse(source.contains("CompactActionButton"))
        XCTAssertFalse(source.contains("管理账号"))
        XCTAssertFalse(source.contains("Quota Targets"))
    }

    func testAppShellUsesRenderedTemplateImageForMenuBarExtra() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/AiUsageApp.swift")
        XCTAssertTrue(source.contains("QuotaMenuBarImageRenderer"))
        XCTAssertTrue(source.contains("Image(nsImage:"))
        XCTAssertFalse(source.contains("chart.bar.xaxis"))
    }

    func testSettingsSourceIncludesProviderToggleSection() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/SettingsView.swift")
        XCTAssertTrue(source.contains("账号与来源"))
        XCTAssertTrue(source.contains("当前状态"))
        XCTAssertTrue(source.contains("套餐额度"))
        XCTAssertTrue(source.contains("Text(\"第三方 API\")"))
        XCTAssertTrue(source.contains("Quota URL"))
        XCTAssertTrue(source.contains("API Key"))
        XCTAssertFalse(source.contains("Quota 服务"))
        XCTAssertFalse(source.contains("Group ID"))
    }

    func testMiMoLoginSourceUsesOfficialWebLogin() throws {
        let credentialSource = try sourceText(path: "App/Sources/AiUsage/Views/MiMoCredentialFields.swift")
        let windowSource = try sourceText(path: "App/Sources/AiUsage/Views/MiMoWebLoginWindowView.swift")
        XCTAssertTrue(credentialSource.contains("登录小米账号"))
        XCTAssertTrue(credentialSource.contains("openWindow(id: \"mimo-login\")"))
        XCTAssertTrue(windowSource.contains("MiMoWebLoginView"))
        XCTAssertTrue(windowSource.contains("storeWebSession(token:"))
        XCTAssertTrue(windowSource.contains("markMiMoLoginCompleted()"))
        XCTAssertFalse(credentialSource.contains("SecureField(\"密码\""))
        XCTAssertFalse(credentialSource.contains("登录并查询"))
        XCTAssertFalse(credentialSource.contains("手动导入"))
        XCTAssertFalse(credentialSource.contains("Cookie"))
    }

    func testMiMoWebLoginUsesDedicatedWindowNotMenuBarSheet() throws {
        let credentialSource = try sourceText(path: "App/Sources/AiUsage/Views/MiMoCredentialFields.swift")
        let appSource = try sourceText(path: "App/Sources/AiUsage/AiUsageApp.swift")

        XCTAssertFalse(credentialSource.contains(".sheet(isPresented: $isShowingWebLogin)"))
        XCTAssertFalse(credentialSource.contains("@State private var isShowingWebLogin"))
        XCTAssertTrue(appSource.contains("Window(\"MiMo 登录\", id: \"mimo-login\")"))
        XCTAssertTrue(appSource.contains("MiMoWebLoginWindowView"))
        XCTAssertTrue(credentialSource.contains("openWindow(id: \"mimo-login\")"))
    }

    func testRootViewDoesNotInstantiateHeadlessMiMoSSOForWebLogin() throws {
        let rootSource = try sourceText(path: "App/Sources/AiUsage/Views/RootView.swift")
        let windowSource = try sourceText(path: "App/Sources/AiUsage/Views/MiMoWebLoginWindowView.swift")
        XCTAssertFalse(rootSource.contains("MiMoSSOAuthService"))
        XCTAssertFalse(windowSource.contains("MiMoSSOAuthService"))
    }

    func testQuotaSummarySourceUsesVisibleWindowsForDynamicCards() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/QuotaSummaryViews.swift")
        XCTAssertTrue(source.contains("QuotaProgressRiskLevel"))
        XCTAssertTrue(source.contains("summary.visibleWindows"))
        XCTAssertTrue(source.contains("ForEach(windows)"))
        XCTAssertFalse(source.contains("summary.fiveHour"))
        XCTAssertFalse(source.contains("summary.weekly"))
        XCTAssertFalse(source.contains("Text(summary.title)"))
        XCTAssertTrue(source.contains("window.secondaryText"))
    }

    func testMenuBarGlyphUsesVisibleWindowProgress() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Services/MenuBarSummaryReadModelService.swift")
        XCTAssertTrue(source.contains("summary.visibleWindows"))
        XCTAssertTrue(source.contains("rightRatio: rightProgress"))
        XCTAssertFalse(source.contains("summary.secondaryWindow.progress ?? 0.18"))
    }

    func testMiMoKeychainReadsDisallowAuthenticationUI() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Services/EntitlementPreferences.swift")
        XCTAssertTrue(source.contains("LAContext"))
        XCTAssertTrue(source.contains("interactionNotAllowed = true"))
        XCTAssertTrue(source.contains("kSecUseAuthenticationContext as String"))
        XCTAssertTrue(source.contains("kSecUseAuthenticationUI as String"))
        XCTAssertTrue(source.contains("kSecUseAuthenticationUISkip"))
        XCTAssertTrue(source.contains("DispatchSemaphore"))
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
