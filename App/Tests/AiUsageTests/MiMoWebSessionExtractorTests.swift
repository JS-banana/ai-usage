import XCTest
@testable import AiUsage

final class MiMoWebSessionExtractorTests: XCTestCase {
    func testExtractsServiceTokenFromOfficialPlatformCookies() throws {
        let acquiredAt = Date(timeIntervalSince1970: 1_800)

        let token = try MiMoWebSessionExtractor.extractToken(
            from: [
                MiMoWebCookie(name: "api-platform_serviceToken", value: "svc"),
                MiMoWebCookie(name: "userId", value: "12345"),
                MiMoWebCookie(name: "api-platform_slh", value: "slh"),
                MiMoWebCookie(name: "api-platform_ph", value: "ph"),
                MiMoWebCookie(name: "unrelated", value: "ignored")
            ],
            acquiredAt: acquiredAt
        )

        XCTAssertEqual(token.serviceToken, "svc")
        XCTAssertEqual(token.userId, "12345")
        XCTAssertEqual(token.slh, "slh")
        XCTAssertEqual(token.ph, "ph")
        XCTAssertEqual(token.acquiredAt, acquiredAt)
    }

    func testReportsMissingCookieNames() {
        XCTAssertThrowsError(try MiMoWebSessionExtractor.extractToken(
            from: [
                MiMoWebCookie(name: "api-platform_serviceToken", value: "svc"),
                MiMoWebCookie(name: "userId", value: "12345")
            ],
            acquiredAt: Date()
        )) { error in
            guard case MiMoWebSessionExtractor.ExtractionError.missingCookies(let names) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(names, ["api-platform_slh", "api-platform_ph"])
        }
    }

    func testTreatsEmptyCookieValuesAsMissing() {
        XCTAssertThrowsError(try MiMoWebSessionExtractor.extractToken(
            from: [
                MiMoWebCookie(name: "api-platform_serviceToken", value: ""),
                MiMoWebCookie(name: "userId", value: "12345"),
                MiMoWebCookie(name: "api-platform_slh", value: "slh"),
                MiMoWebCookie(name: "api-platform_ph", value: "ph")
            ],
            acquiredAt: Date()
        )) { error in
            guard case MiMoWebSessionExtractor.ExtractionError.missingCookies(let names) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(names, ["api-platform_serviceToken"])
        }
    }

    func testStripsOuterQuotesFromCookieValues() throws {
        let token = try MiMoWebSessionExtractor.extractToken(
            from: [
                MiMoWebCookie(name: "api-platform_serviceToken", value: "\"svc\""),
                MiMoWebCookie(name: "userId", value: "12345"),
                MiMoWebCookie(name: "api-platform_slh", value: "\"slh\""),
                MiMoWebCookie(name: "api-platform_ph", value: "\"ph\"")
            ],
            acquiredAt: Date()
        )

        XCTAssertEqual(token.serviceToken, "svc")
        XCTAssertEqual(token.slh, "slh")
        XCTAssertEqual(token.ph, "ph")
        XCTAssertEqual(token.cookieValue, "api-platform_serviceToken=\"svc\"; userId=12345; api-platform_slh=\"slh\"; api-platform_ph=\"ph\"")
    }
}
