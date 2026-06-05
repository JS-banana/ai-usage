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
            for: QuotaMenuBarGlyphState.dualWindows(leftRatio: 0.25, rightRatio: 0.6, isDimmed: false)
        )

        XCTAssertEqual(image.size.width, 18)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertTrue(image.isTemplate)
    }

    func testRenderedMenuBarImageDrawsTrackAndFillForDualWindows() {
        let renderer = QuotaMenuBarImageRenderer()
        let image = renderer.image(for: .dualWindows(leftRatio: 0.86, rightRatio: 0.42, isDimmed: false))

        XCTAssertTrue(visibleAlphas(image).contains { $0 > 0.9 })
        XCTAssertTrue(visibleAlphas(image).contains { $0 > 0.15 && $0 < 0.5 })
        XCTAssertEqual(alphaColumnRuns(image, y: 8).count, 2)
    }

    func testRenderedMenuBarImageDrawsSingleMiMoTankWithTrackContrast() {
        let renderer = QuotaMenuBarImageRenderer()
        let single = renderer.image(for: .singlePlan(ratio: 0.84, isDimmed: false))
        let dual = renderer.image(for: .dualWindows(leftRatio: 0.84, rightRatio: 0.84, isDimmed: false))

        let singleRuns = alphaColumnRuns(single, y: 8)
        XCTAssertEqual(singleRuns.count, 1)
        XCTAssertGreaterThanOrEqual(singleRuns.first?.count ?? 0, 8)
        XCTAssertLessThan(visibleAlphaBounds(single).width, visibleAlphaBounds(dual).width)
        XCTAssertTrue(visibleAlphas(single).contains { $0 > 0.9 })
        XCTAssertTrue(visibleAlphas(single).contains { $0 > 0.15 && $0 < 0.5 })
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
        XCTAssertFalse(source.contains("重新配置额度"))
    }

    func testAppShellUsesRenderedTemplateImageForMenuBarExtra() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/AiUsageApp.swift")
        XCTAssertTrue(source.contains("QuotaMenuBarImageRenderer"))
        XCTAssertTrue(source.contains("Image(nsImage:"))
        XCTAssertTrue(source.contains(".id(appState.menuBarSummary.glyph)"))
        XCTAssertFalse(source.contains("chart.bar.xaxis"))
    }

    func testSettingsSourceIncludesProviderToggleSection() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/SettingsView.swift")
        XCTAssertTrue(source.contains("Agent 显示"))
        XCTAssertTrue(source.contains("当前状态"))
        XCTAssertTrue(source.contains("本机 usage 统计"))
        XCTAssertFalse(source.contains("账号与来源"))
        XCTAssertFalse(source.contains("套餐额度"))
        XCTAssertFalse(source.contains("Text(\"第三方 API\")"))
        XCTAssertFalse(source.contains("Quota URL"))
        XCTAssertFalse(source.contains("API Key"))
        XCTAssertFalse(source.contains("Quota 服务"))
        XCTAssertFalse(source.contains("Group ID"))
    }

    func testSettingsActionActivatesAndOrdersWindowFront() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/RootView.swift")
        XCTAssertTrue(source.contains("openSettingsFrontmost()"))
        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(source.contains("NSApp.windows"))
        XCTAssertTrue(source.contains("orderFrontRegardless()"))
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
        XCTAssertTrue(source.contains("chunked(into: 2)"))
        XCTAssertTrue(source.contains("ForEach(Array(windows.chunked"))
        XCTAssertTrue(source.contains("ForEach(row)"))
        XCTAssertTrue(source.contains("HStack(alignment: .firstTextBaseline"))
        XCTAssertTrue(source.contains("window.detailText"))
        XCTAssertTrue(source.contains("if window.progress != nil"))
        XCTAssertFalse(source.contains("summary.fiveHour"))
        XCTAssertFalse(source.contains("summary.weekly"))
        XCTAssertFalse(source.contains("Text(summary.title)"))
        XCTAssertTrue(source.contains("window.secondaryText"))
    }

    func testEntitlementSummarySupportsExtraWindows() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Models/EntitlementModels.swift")
        XCTAssertTrue(source.contains("let extraWindows: [EntitlementWindowSnapshot]"))
        XCTAssertTrue(source.contains("extraWindows: [EntitlementWindowSnapshot] = []"))
        XCTAssertTrue(source.contains("detailText: String = \"\""))
        XCTAssertTrue(source.contains("([primaryWindow, secondaryWindow] + extraWindows).filter"))
    }

    func testMenuBarRendererDrawsLowAlphaCapacityTrack() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/MenuBar/QuotaMenuBarImageRenderer.swift")
        XCTAssertTrue(source.contains("drawTrack"))
        XCTAssertTrue(source.contains("trackAlpha"))
        XCTAssertTrue(source.contains("fillAlpha"))
        XCTAssertTrue(source.contains("singlePlan"))
    }

    func testMenuBarGlyphStateIsSchemaAware() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Services/MenuBarSummaryReadModelService.swift")
        XCTAssertTrue(source.contains("enum QuotaMenuBarGlyphState"))
        XCTAssertTrue(source.contains("case singlePlan"))
        XCTAssertTrue(source.contains("case dualWindows"))
        XCTAssertTrue(source.contains("case empty"))
        XCTAssertTrue(source.contains("sourceKind == .mimo"))
        XCTAssertTrue(source.contains("menuBarProgress"))
        XCTAssertTrue(source.contains("remainingRatio"))
        XCTAssertFalse(source.contains("rightRatio: remainingProgress"))
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
        XCTAssertTrue(source.contains("PanelDetailCard(title: \"套餐额度\", trailing:"))
        XCTAssertTrue(source.contains("refreshCurrentEntitlement()"))
        XCTAssertTrue(source.contains("summary.status != .unconfigured"))
        XCTAssertFalse(source.contains("appState.groupQuotaSummary"))
    }

    func testQuotaRefreshControlsUseEntitlementRefreshState() throws {
        let appStateSource = try sourceText(path: "App/Sources/AiUsage/Models/AppState.swift")
        let rootSource = try sourceText(path: "App/Sources/AiUsage/Views/RootView.swift")
        let providerDetailSource = try sourceText(path: "App/Sources/AiUsage/Views/ProviderDetailView.swift")
        let settingsSource = try sourceText(path: "App/Sources/AiUsage/Views/SettingsView.swift")
        let quotaManagementSource = try sourceText(path: "App/Sources/AiUsage/Views/QuotaManagementView.swift")

        XCTAssertTrue(appStateSource.contains("isEntitlementRefreshInProgress"))
        XCTAssertTrue(rootSource.contains(".disabled(appState.isEntitlementRefreshInProgress)"))
        XCTAssertTrue(providerDetailSource.contains(".disabled(appState.isEntitlementRefreshInProgress)"))
        XCTAssertFalse(settingsSource.contains("refreshCurrentEntitlement()"))
        XCTAssertTrue(quotaManagementSource.contains("refresh()"))
    }

    func testQuotaManagementKeepsAddAccountAvailableWhenEmpty() throws {
        let source = try sourceText(path: "App/Sources/AiUsage/Views/QuotaManagementView.swift")
        XCTAssertTrue(source.contains("暂无额度账号"))
        XCTAssertTrue(source.contains("addMiMoAccount()"))
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

    private func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiffData)
    }

    private func visibleAlphas(_ image: NSImage) -> [CGFloat] {
        guard let bitmap = bitmap(from: image) else { return [] }
        var alphas: [CGFloat] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha > 0.05 {
                    alphas.append(alpha)
                }
            }
        }
        return alphas
    }

    private func alphaColumnRuns(_ image: NSImage, y: Int) -> [[Int]] {
        guard let bitmap = bitmap(from: image) else { return [] }
        var runs: [[Int]] = []
        var current: [Int] = []
        for x in 0..<bitmap.pixelsWide {
            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if alpha > 0.05 {
                current.append(x)
            } else if current.isEmpty == false {
                runs.append(current)
                current = []
            }
        }
        if current.isEmpty == false {
            runs.append(current)
        }
        return runs
    }

    private func visibleAlphaBounds(_ image: NSImage) -> CGRect {
        guard let bitmap = bitmap(from: image) else { return .null }
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                guard alpha > 0.05 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return .null }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
