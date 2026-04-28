import XCTest
@testable import AiUsage

final class LaifuyouQuotaServiceTests: XCTestCase {
    func testFetchMapsBridgeResponseToEntitlementWindows() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.resetCapture()

        let service = LaifuyouQuotaService(session: session)
        let payload = try await service.fetch(
            configuration: BridgeEntitlementConfiguration(
                endpointURL: URL(string: "https://quota.laifuyou.com/quota-summary?group_id=2")!,
                apiKey: "test-key"
            ),
            targetID: .overview,
            title: "总览套餐",
            now: Date(timeIntervalSince1970: 1_745_410_000)
        )

        XCTAssertEqual(payload.title, "总览套餐")
        XCTAssertEqual(payload.primaryWindow.title, "5h")
        XCTAssertEqual(payload.secondaryWindow.title, "7d")
        XCTAssertEqual(payload.primaryWindow.progress ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(payload.secondaryWindow.progress ?? 0, 0.4, accuracy: 0.001)
        XCTAssertTrue(payload.primaryWindow.footnoteText.contains(":"))
        XCTAssertFalse(payload.primaryWindow.footnoteText.contains("后"))
        XCTAssertEqual(MockURLProtocol.capturedURL(), "https://quota.laifuyou.com/quota-summary?group_id=2")
        XCTAssertEqual(MockURLProtocol.capturedAuthorization(), "Bearer test-key")
    }

    func testLegacyGroupConfigurationStillBuildsEndpointURL() {
        let defaults = UserDefaults(suiteName: "LaifuyouQuotaServiceLegacyTests")!
        defaults.removePersistentDomain(forName: "LaifuyouQuotaServiceLegacyTests")
        defaults.set("test-key", forKey: LaifuyouQuotaConfiguration.apiKeyDefaultsKey)
        defaults.set("9", forKey: LaifuyouQuotaConfiguration.legacyGroupIDDefaultsKey)

        let config = LaifuyouQuotaConfiguration.legacyCurrent(userDefaults: defaults)

        XCTAssertEqual(config?.endpointURL.absoluteString, "https://quota.laifuyou.com/quota-summary?group_id=9")
    }

    func testOverviewConfigurationSeedsFromLegacyOnlyOnce() {
        let defaults = UserDefaults(suiteName: "EntitlementPreferencesLegacySeedTests")!
        defaults.removePersistentDomain(forName: "EntitlementPreferencesLegacySeedTests")
        defaults.set("legacy-key", forKey: LaifuyouQuotaConfiguration.apiKeyDefaultsKey)
        defaults.set("https://quota.example.com/summary", forKey: LaifuyouQuotaConfiguration.endpointURLDefaultsKey)

        let first = EntitlementPreferences.configuration(for: .overview, userDefaults: defaults)
        XCTAssertEqual(first.selectedSource, .thirdParty)
        XCTAssertEqual(first.bridgeConfiguration?.apiKey, "legacy-key")

        EntitlementPreferences.setBridgeAPIKey("new-key", for: .overview, userDefaults: defaults)
        let second = EntitlementPreferences.configuration(for: .overview, userDefaults: defaults)
        XCTAssertEqual(second.bridgeConfiguration?.apiKey, "new-key")
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let captureSuiteName = "LaifuyouQuotaServiceCapture"
    private static let urlKey = "capturedURL"
    private static let authorizationKey = "capturedAuthorization"
    static let responseData = #"{"group":{"id":2,"name":"测试组"},"group_id":2,"accounts_total":2,"accounts_active":1,"quota_5h":{"capacity_units":5,"used_units":1.5,"remaining_units":3.5,"remaining_percent":70,"next_reset_at":"2026-04-23T18:48:59+08:00","latest_reset_at":"2026-04-24T00:45:42+08:00"},"quota_7d":{"capacity_units":5,"used_units":2.0,"remaining_units":3.0,"remaining_percent":60,"next_reset_at":"2026-04-29T04:00:33+08:00","latest_reset_at":"2026-04-29T10:57:32+08:00"},"updated_at":"2026-04-23T11:45:57.839176+00:00"}"#.data(using: .utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let defaults = UserDefaults(suiteName: Self.captureSuiteName)!
        defaults.set(request.url?.absoluteString, forKey: Self.urlKey)
        defaults.set(request.value(forHTTPHeaderField: "Authorization"), forKey: Self.authorizationKey)

        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func resetCapture() {
        UserDefaults(suiteName: captureSuiteName)?.removePersistentDomain(forName: captureSuiteName)
    }

    static func capturedURL() -> String? {
        UserDefaults(suiteName: captureSuiteName)?.string(forKey: urlKey)
    }

    static func capturedAuthorization() -> String? {
        UserDefaults(suiteName: captureSuiteName)?.string(forKey: authorizationKey)
    }
}
