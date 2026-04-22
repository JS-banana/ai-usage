import XCTest
import Support

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

    func testRootViewSourceUsesOverviewTabAndNoScrollView() throws {
        let source = try sourceText(path: "App/Sources/AIUsageLocal/Views/RootView.swift")
        XCTAssertTrue(source.contains("总览"))
        XCTAssertFalse(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("selectedTabID == \"overview\""))
        XCTAssertTrue(source.contains("onContinuousHover"))
    }

    func testAppShellUsesMenuBarExtra() throws {
        let source = try sourceText(path: "App/Sources/AIUsageLocal/AIUsageLocalApp.swift")
        XCTAssertTrue(source.contains("MenuBarExtra"))
        XCTAssertTrue(source.contains("WindowGroup(\"AI Usage Local\", id: \"detail\")"))
    }

    private func sourceText(path: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // AIUsageLocalTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // repo root
        return try String(contentsOf: repoRoot.appendingPathComponent(path))
    }
}
