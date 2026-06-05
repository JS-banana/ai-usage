import XCTest
@testable import AiUsage

final class EntitlementSourceSelectionTests: XCTestCase {
    func testMiMoRawValueIsMimo() {
        XCTAssertEqual(EntitlementSourceSelection.mimo.rawValue, "mimo")
    }

    func testMiMoCanBeInitializedFromRawValue() {
        XCTAssertEqual(EntitlementSourceSelection(rawValue: "mimo"), .mimo)
    }

    func testAllCasesContainsMiMo() {
        XCTAssertTrue(EntitlementSourceSelection.allCases.contains(.mimo))
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(EntitlementSourceSelection(rawValue: "invalid"))
    }
}
