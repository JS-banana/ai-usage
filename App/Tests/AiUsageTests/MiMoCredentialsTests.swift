import XCTest
@testable import AiUsage

final class MiMoCredentialsTests: XCTestCase {
    func testCredentialsEquality() {
        let a = MiMoCredentials(username: "user", passwordMD5: "ABC123")
        let b = MiMoCredentials(username: "user", passwordMD5: "ABC123")
        XCTAssertEqual(a, b)
    }

    func testCredentialsInequality() {
        let a = MiMoCredentials(username: "user1", passwordMD5: "ABC")
        let b = MiMoCredentials(username: "user2", passwordMD5: "ABC")
        XCTAssertNotEqual(a, b)
    }
}

final class MiMoServiceTokenTests: XCTestCase {
    func testCookieValueFormat() {
        let token = MiMoServiceToken(
            serviceToken: "tok123",
            userId: "456",
            slh: "slh_val",
            ph: "ph_val",
            acquiredAt: Date()
        )
        let cookie = token.cookieValue
        XCTAssertTrue(cookie.contains("api-platform_serviceToken=\"tok123\""))
        XCTAssertTrue(cookie.contains("userId=456"))
        XCTAssertTrue(cookie.contains("api-platform_slh=\"slh_val\""))
        XCTAssertTrue(cookie.contains("api-platform_ph=\"ph_val\""))
    }

    func testCookieValueNormalizesPersistedQuotedComponents() {
        let token = MiMoServiceToken(
            serviceToken: "\"tok123\"",
            userId: "456",
            slh: "\"slh_val\"",
            ph: "\"ph_val\"",
            acquiredAt: Date()
        )

        XCTAssertEqual(
            token.cookieValue,
            "api-platform_serviceToken=\"tok123\"; userId=456; api-platform_slh=\"slh_val\"; api-platform_ph=\"ph_val\""
        )
    }

    func testTokenNotExpiredWithinOneHour() {
        let token = MiMoServiceToken(
            serviceToken: "t",
            userId: "u",
            slh: "s",
            ph: "p",
            acquiredAt: Date().addingTimeInterval(-1800)
        )
        XCTAssertFalse(token.isExpired)
    }

    func testTokenNeverExpired() {
        let token = MiMoServiceToken(
            serviceToken: "t",
            userId: "u",
            slh: "s",
            ph: "p",
            acquiredAt: Date().addingTimeInterval(-7200)
        )
        XCTAssertFalse(token.isExpired, "isExpired should always return false; expiry is determined by 401 response")
    }
}
