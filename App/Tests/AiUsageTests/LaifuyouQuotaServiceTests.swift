import XCTest
@testable import AiUsage

final class LaifuyouQuotaServiceTests: XCTestCase {
    func testFetchIfConfiguredMapsResponseToGroupTotalWindowsOnly() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let defaults = UserDefaults(suiteName: "LaifuyouQuotaServiceTests")!
        defaults.removePersistentDomain(forName: "LaifuyouQuotaServiceTests")
        defaults.set("test-key", forKey: LaifuyouQuotaConfiguration.apiKeyDefaultsKey)
        defaults.set("https://quota.laifuyou.com/quota-summary?group_id=2", forKey: LaifuyouQuotaConfiguration.endpointURLDefaultsKey)
        MockURLProtocol.resetCapture()

        let service = LaifuyouQuotaService(session: session, userDefaults: defaults)

        let payload = try await service.fetchIfConfigured(now: Date(timeIntervalSince1970: 1_745_410_000))

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.groupID, 2)
        XCTAssertEqual(payload?.groupName, "测试组")
        XCTAssertEqual(payload?.fiveHour.title, "5h")
        XCTAssertEqual(payload?.weekly.title, "周")
        XCTAssertEqual(payload?.fiveHour.progress ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(payload?.weekly.progress ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(MockURLProtocol.capturedURL(), "https://quota.laifuyou.com/quota-summary?group_id=2")
        XCTAssertEqual(MockURLProtocol.capturedAuthorization(), "Bearer test-key")
    }

    func testLegacyGroupConfigurationStillBuildsEndpointURL() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let defaults = UserDefaults(suiteName: "LaifuyouQuotaServiceLegacyTests")!
        defaults.removePersistentDomain(forName: "LaifuyouQuotaServiceLegacyTests")
        defaults.set("test-key", forKey: LaifuyouQuotaConfiguration.apiKeyDefaultsKey)
        defaults.set("9", forKey: LaifuyouQuotaConfiguration.legacyGroupIDDefaultsKey)
        MockURLProtocol.resetCapture()

        let service = LaifuyouQuotaService(session: session, userDefaults: defaults)
        _ = try await service.fetchIfConfigured(now: Date(timeIntervalSince1970: 1_745_410_000))

        XCTAssertEqual(MockURLProtocol.capturedURL(), "https://quota.laifuyou.com/quota-summary?group_id=9")
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let captureSuiteName = "LaifuyouQuotaServiceCapture"
    private static let urlKey = "capturedURL"
    private static let authorizationKey = "capturedAuthorization"
    static let responseData = #"{"group":{"id":2,"name":"测试组"},"group_id":2,"accounts_total":2,"accounts_active":1,"quota_5h":{"capacity_units":5,"used_units":1.5,"remaining_units":3.5,"remaining_percent":70,"next_reset_at":"2026-04-23T18:48:59+08:00","latest_reset_at":"2026-04-24T00:45:42+08:00"},"quota_7d":{"capacity_units":5,"used_units":2.0,"remaining_units":3.0,"remaining_percent":60,"next_reset_at":"2026-04-29T04:00:33+08:00","latest_reset_at":"2026-04-29T10:57:32+08:00"},"accounts":[{"id":2,"name":"账号A","status":"active","used_5h_percent":25.0,"reset_5h_at":"2026-04-23T19:45:47+08:00","used_7d_percent":57.0,"reset_7d_at":"2026-04-29T09:24:11+08:00"}],"updated_at":"2026-04-23T11:45:57.839176+00:00"}"#.data(using: .utf8)

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
