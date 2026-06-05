import XCTest
@testable import AiUsage

final class MiMoAccountTests: XCTestCase {

    func testAccountHasIDCredentialsAndDisplayName() {
        let creds = MiMoCredentials(username: "user1", passwordMD5: "ABC123")
        let account = MiMoAccount(id: UUID(), credentials: creds, displayName: "My Account")

        XCTAssertEqual(account.credentials, creds)
        XCTAssertEqual(account.displayName, "My Account")
    }

    func testAccountFromCredentialsUsesUsernameAsDefaultDisplayName() {
        let creds = MiMoCredentials(username: "user1", passwordMD5: "ABC123")
        let account = MiMoAccount(credentials: creds)

        XCTAssertEqual(account.displayName, "user1")
        XCTAssertEqual(account.credentials, creds)
    }

    func testAccountEqualityBasedOnID() {
        let id = UUID()
        let creds = MiMoCredentials(username: "user1", passwordMD5: "ABC123")
        let a = MiMoAccount(id: id, credentials: creds, displayName: "A")
        let b = MiMoAccount(id: id, credentials: creds, displayName: "B")

        XCTAssertEqual(a, b)
    }

    func testAccountInequalityBasedOnID() {
        let creds = MiMoCredentials(username: "user1", passwordMD5: "ABC123")
        let a = MiMoAccount(id: UUID(), credentials: creds, displayName: "A")
        let b = MiMoAccount(id: UUID(), credentials: creds, displayName: "A")

        XCTAssertNotEqual(a, b)
    }

    func testAccountIsIdentifiable() {
        let account = MiMoAccount(credentials: MiMoCredentials(username: "u", passwordMD5: "x"))
        XCTAssertFalse(account.id.uuidString.isEmpty)
    }

    func testAccountIsHashable() {
        let id = UUID()
        let creds = MiMoCredentials(username: "u", passwordMD5: "x")
        let a = MiMoAccount(id: id, credentials: creds)
        let b = MiMoAccount(id: id, credentials: creds)

        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testAccountIsSendable() {
        // Compile-time check: MiMoAccount conforms to Sendable
        let account: Sendable = MiMoAccount(credentials: MiMoCredentials(username: "u", passwordMD5: "x"))
        XCTAssertNotNil(account)
    }
}
