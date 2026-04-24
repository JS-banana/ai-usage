import XCTest
@testable import AiUsage

@MainActor
final class AppStateTests: XCTestCase {
    func testBootstrapFailureSurfacesStatusInsteadOfCrashing() async {
        let state = AppState(bootstrapError: BootstrapTestError.failed)

        XCTAssertEqual(state.statusMessage, "启动失败：示例故障")
        XCTAssertFalse(state.hasBootstrapped)

        await state.startIfNeeded()

        XCTAssertTrue(state.hasBootstrapped)
        XCTAssertEqual(state.statusMessage, "启动失败：示例故障")
    }
}

private enum BootstrapTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "示例故障"
    }
}
