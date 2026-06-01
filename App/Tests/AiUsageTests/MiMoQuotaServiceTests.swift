import XCTest
@testable import AiUsage

final class MiMoQuotaServiceTests: XCTestCase {

    // MARK: - Happy Path

    func testFetchMapsUsageResponseToEntitlementWindows() async throws {
        let json = """
        {
            "code": 0,
            "data": {
                "monthUsage": {
                    "percent": 0.4475,
                    "items": [{"name": "month_total_token", "used": 89501986, "limit": 200000000, "percent": 0.4475}]
                },
                "usage": {
                    "percent": 0.45,
                    "items": [
                        {"name": "plan_total_token", "used": 89501986, "limit": 200000000, "percent": 0.45},
                        {"name": "compensation_total_token", "used": 0, "limit": 0, "percent": 0}
                    ]
                }
            }
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.title, "MiMo")
        XCTAssertEqual(snapshot.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "已用 45%")
        XCTAssertTrue(snapshot.primaryWindow.secondaryText.contains("token"))
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "到期时间未返回")
        XCTAssertEqual(snapshot.primaryWindow.progress ?? 0, 0.45, accuracy: 0.001)
        XCTAssertFalse(snapshot.secondaryWindow.isVisible)
        XCTAssertEqual(snapshot.sourceKind, .mimo)
        XCTAssertTrue(snapshot.primaryWindow.secondaryText.contains("8950.2万"))
        XCTAssertTrue(snapshot.primaryWindow.secondaryText.contains("2亿"))
    }

    func testFetchShowsCompensationWindowWhenCompensationHasLimit() async throws {
        let json = """
        {
            "code": 0,
            "data": {
                "monthUsage": {
                    "percent": 0.1258,
                    "items": [{"name": "month_total_token", "used": 1384262264, "limit": 11000000000, "percent": 0.1258}]
                },
                "usage": {
                    "percent": 0,
                    "items": [
                        {"name": "plan_total_token", "used": 0, "limit": 11000000000, "percent": 0},
                        {"name": "compensation_total_token", "used": 1384262264, "limit": 3285714286, "percent": 0.42}
                    ]
                }
            }
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "已用 0%")
        XCTAssertTrue(snapshot.primaryWindow.secondaryText.contains("0 / 110亿 token"))
        XCTAssertEqual(snapshot.secondaryWindow.title, "补偿额度")
        XCTAssertEqual(snapshot.secondaryWindow.primaryText, "已用 42%")
        XCTAssertTrue(snapshot.secondaryWindow.secondaryText.contains("13.84亿"))
        XCTAssertTrue(snapshot.secondaryWindow.secondaryText.contains("32.86亿"))
        XCTAssertEqual(snapshot.secondaryWindow.footnoteText, "到期时间未返回")
        XCTAssertEqual(snapshot.secondaryWindow.progress ?? 0, 0.42, accuracy: 0.001)
        XCTAssertTrue(snapshot.secondaryWindow.isVisible)
    }

    func testFetchMapsExpiryWhenResponseProvidesExpireAt() async throws {
        let json = """
        {
            "code": 0,
            "data": {
                "expireAt": "2026-07-01T00:00:00+08:00",
                "monthUsage": {
                    "percent": 0.2,
                    "items": [{"name": "month_total_token", "used": 20, "limit": 100, "percent": 0.2}]
                },
                "usage": {
                    "percent": 0.2,
                    "items": [
                        {"name": "plan_total_token", "used": 20, "limit": 100, "percent": 0.2}
                    ]
                }
            }
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertTrue(snapshot.primaryWindow.footnoteText.contains("到期"))
        XCTAssertFalse(snapshot.primaryWindow.footnoteText.contains("未返回"))
    }

    func testFetchUsesTokenPlanDetailExpiryWhenUsageHasNoExpiry() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"plan":{"expireAt":"2026-08-15T00:00:00+08:00"}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, ["/api/v1/tokenPlan/usage", "/api/v1/tokenPlan/detail"])
        XCTAssertTrue(snapshot.primaryWindow.footnoteText.contains("到期"))
        XCTAssertFalse(snapshot.primaryWindow.footnoteText.contains("未返回"))
    }

    func testFetchUsesTokenPlanDetailExpiryFromExpireTimeField() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"tokenPlan":{"expireTime":"2026-08-15 23:59:59"}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, ["/api/v1/tokenPlan/usage", "/api/v1/tokenPlan/detail"])
        XCTAssertTrue(snapshot.primaryWindow.footnoteText.contains("2026"))
        XCTAssertFalse(snapshot.primaryWindow.footnoteText.contains("未返回"))
    }

    func testFetchUsesTokenPlanDetailExpiryFromSnakeCaseMillisecondTimestamp() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"tokenPlan":{"expire_time":1786809599000}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, ["/api/v1/tokenPlan/usage", "/api/v1/tokenPlan/detail"])
        XCTAssertTrue(snapshot.primaryWindow.footnoteText.contains("2026"))
        XCTAssertFalse(snapshot.primaryWindow.footnoteText.contains("未返回"))
    }

    func testFetchKeepsUsageWhenTokenPlanDetailFails() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([(usageJSON, 200), ("{}", 500)])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "到期时间未返回")
    }

    func testFetchSetsStatusReadyWhenTokenFresh() async throws {
        let json = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.status, .ready)
    }

    func testFetchSetsStatusReadyEvenWhenTokenOld() async throws {
        let json = standardJSON(monthPercent: 0.5, planPercent: 0.6)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        // isExpired is always false; expiry is determined by 401 response, not age
        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date().addingTimeInterval(-7200))
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.status, .ready)
    }

    func testFetchSendsCorrectCookieHeader() async throws {
        let json = standardJSON(monthPercent: 0.1, planPercent: 0.1)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "my_tok", userId: "99", slh: "my_slh", ph: "my_ph", acquiredAt: Date())
        _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        let cookie = mock.capturedRequest?.value(forHTTPHeaderField: "Cookie") ?? ""
        XCTAssertTrue(cookie.contains("api-platform_serviceToken=\"my_tok\""))
        XCTAssertTrue(cookie.contains("userId=99"))
    }

    func testFetchSendsBrowserCompatibleHeaders() async throws {
        let json = standardJSON(monthPercent: 0.1, planPercent: 0.1)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "my_tok", userId: "99", slh: "my_slh", ph: "my_ph", acquiredAt: Date())
        _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        let request = try XCTUnwrap(mock.capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/plain, */*")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://platform.xiaomimimo.com/console/plan-manage")
        XCTAssertTrue((request.value(forHTTPHeaderField: "User-Agent") ?? "").contains("Mozilla/5.0"))
    }

    func testFetchCallsCorrectEndpoint() async throws {
        let json = standardJSON(monthPercent: 0.1, planPercent: 0.1)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "t", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        let request = try XCTUnwrap(mock.capturedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    // MARK: - Edge Cases

    func testFetchHandlesZeroLimitGracefully() async throws {
        let json = """
        {
            "code": 0,
            "data": {
                "monthUsage": {"percent": 0, "items": [{"name": "month_total_token", "used": 0, "limit": 0, "percent": 0}]},
                "usage": {"percent": 0, "items": [
                    {"name": "plan_total_token", "used": 0, "limit": 0, "percent": 0},
                    {"name": "compensation_total_token", "used": 0, "limit": 0, "percent": 0}
                ]}
            }
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.progress, 0)
        XCTAssertFalse(snapshot.secondaryWindow.isVisible)
        XCTAssertFalse(snapshot.primaryWindow.primaryText.isEmpty)
    }

    // MARK: - Error Cases

    func testFetchThrowsUnauthorizedOn401() async {
        let mock = MockQuotaHTTPClient(statusCode: 401)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "bad", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        do {
            _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())
            XCTFail("Expected unauthorized error")
        } catch let error as MiMoQuotaService.QuotaError {
            if case .unauthorized = error {} else {
                XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchThrowsDecodingErrorOnInvalidJSON() async {
        let mock = MockQuotaHTTPClient(responseJSON: "not json")
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        do {
            _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())
            XCTFail("Expected decoding error")
        } catch {
            // expected
        }
    }

    func testFetchThrowsNetworkErrorOnURLError() async {
        let mock = MockQuotaHTTPClient(error: URLError(.notConnectedToInternet))
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        do {
            _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())
            XCTFail("Expected network error")
        } catch let error as MiMoQuotaService.QuotaError {
            if case .networkError = error {} else {
                XCTFail("Expected .networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchThrowsServerErrorWhenAPIResponseCodeIsNonZero() async {
        let json = #"{"code":1001,"message":"not logged in","data":{"monthUsage":{"percent":0,"items":[]},"usage":{"percent":0,"items":[]}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        do {
            _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())
            XCTFail("Expected server error for non-zero code")
        } catch let error as MiMoQuotaService.QuotaError {
            if case .serverError(let code, let message) = error {
                XCTAssertEqual(code, 1001)
                XCTAssertEqual(message, "not logged in")
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchThrowsDecodingErrorWhenPlanTotalTokenIsMissing() async {
        let json = """
        {
            "code": 0,
            "data": {
                "monthUsage": {"percent": 0.1, "items": [{"name": "month_total_token", "used": 100, "limit": 200, "percent": 0.5}]},
                "usage": {"percent": 0.2, "items": [{"name": "compensation_total_token", "used": 0, "limit": 0, "percent": 0}]}
            }
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: json)
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        do {
            _ = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())
            XCTFail("Expected decoding error for missing plan_total_token")
        } catch let error as MiMoQuotaService.QuotaError {
            if case .decodingError = error {} else {
                XCTFail("Expected .decodingError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchAll Tests

    func testFetchAllReturnsSnapshotPerAccount() async throws {
        let json = standardJSON(monthPercent: 0.3, planPercent: 0.5)
        let mock = MockQuotaHTTPClient(responseJSON: json, statusCode: 200)
        // fetchAll makes 2 requests via the static helper
        mock.prepareForMultipleRequests(count: 2)
        let service = MiMoQuotaService(client: mock)

        let account1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let account2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let token1 = MiMoServiceToken(serviceToken: "tok1", userId: "u1", slh: "s", ph: "p", acquiredAt: Date())
        let token2 = MiMoServiceToken(serviceToken: "tok2", userId: "u2", slh: "s", ph: "p", acquiredAt: Date())

        let results = await service.fetchAll(
            tokens: [account1: token1, account2: token2],
            targetID: .provider("mimo"),
            title: "MiMo",
            now: Date()
        )

        XCTAssertEqual(results.count, 2)
        let r1 = try XCTUnwrap(results[account1])
        let r2 = try XCTUnwrap(results[account2])
        XCTAssertNotNil(r1.snapshot)
        XCTAssertNil(r1.error)
        XCTAssertNotNil(r2.snapshot)
        XCTAssertNil(r2.error)
    }

    func testFetchAllIsolatesErrors() async throws {
        // Route by token: "bad" → 401, "good" → 200
        let json = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let mock = MockQuotaHTTPClient(responseJSON: json)
        mock.routeByToken["bad"] = (json, 401)
        mock.routeByToken["good"] = (json, 200)
        let service = MiMoQuotaService(client: mock)

        let account1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let account2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let token1 = MiMoServiceToken(serviceToken: "bad", userId: "u1", slh: "s", ph: "p", acquiredAt: Date())
        let token2 = MiMoServiceToken(serviceToken: "good", userId: "u2", slh: "s", ph: "p", acquiredAt: Date())

        let results = await service.fetchAll(
            tokens: [account1: token1, account2: token2],
            targetID: .provider("mimo"),
            title: "MiMo",
            now: Date()
        )

        XCTAssertEqual(results.count, 2)
        let r1 = try XCTUnwrap(results[account1])
        XCTAssertNil(r1.snapshot)
        XCTAssertNotNil(r1.error)
        if let err = r1.error as? MiMoQuotaService.QuotaError {
            if case .unauthorized = err {} else { XCTFail("Expected .unauthorized, got \(err)") }
        }

        let r2 = try XCTUnwrap(results[account2])
        XCTAssertNotNil(r2.snapshot)
        XCTAssertNil(r2.error)
    }

    func testFetchAllWithEmptyTokensReturnsEmpty() async {
        let mock = MockQuotaHTTPClient(responseJSON: "{}", statusCode: 200)
        let service = MiMoQuotaService(client: mock)

        let results = await service.fetchAll(
            tokens: [:],
            targetID: .provider("mimo"),
            title: "MiMo",
            now: Date()
        )

        XCTAssertTrue(results.isEmpty)
        // No request should have been made
        XCTAssertNil(mock.capturedRequest)
    }

    // MARK: - Helpers

    private func standardJSON(monthPercent: Double, planPercent: Double) -> String {
        """
        {
            "code": 0,
            "data": {
                "monthUsage": {"percent": \(monthPercent), "items": [{"name": "month_total_token", "used": 100, "limit": 200, "percent": \(monthPercent)}]},
                "usage": {"percent": \(planPercent), "items": [
                    {"name": "plan_total_token", "used": 100, "limit": 200, "percent": \(planPercent)},
                    {"name": "compensation_total_token", "used": 0, "limit": 0, "percent": 0}
                ]}
            }
        }
        """
    }
}

// MARK: - Mock

private final class MockQuotaHTTPClient: MiMoHTTPClientProtocol, @unchecked Sendable {
    let responseData: Data
    let statusCode: Int
    let error: Error?
    var capturedRequest: URLRequest?
    var capturedRequests: [URLRequest] = []
    var routeByToken: [String: (String, Int)] = [:]  // serviceToken → (responseJSON, statusCode)
    private var responseQueue: [(Data, Int)] = []

    init(responseJSON: String, statusCode: Int = 200) {
        self.responseData = responseJSON.data(using: .utf8)!
        self.statusCode = statusCode
        self.error = nil
    }

    init(statusCode: Int) {
        self.responseData = Data()
        self.statusCode = statusCode
        self.error = nil
    }

    init(error: Error) {
        self.responseData = Data()
        self.statusCode = 0
        self.error = error
    }

    func prepareForMultipleRequests(count: Int, overrideStatusCodes: [Int]? = nil) {
        responseQueue = (0..<count).map { i in
            let code = overrideStatusCodes?[i] ?? statusCode
            return (responseData, code)
        }
    }

    func enqueueResponses(_ responses: [String]) {
        responseQueue = responses.map { ($0.data(using: .utf8)!, 200) }
    }

    func enqueueResponses(_ responses: [(String, Int)]) {
        responseQueue = responses.map { ($0.0.data(using: .utf8)!, $0.1) }
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let error { throw error }
        capturedRequest = request
        capturedRequests.append(request)

        let data: Data
        let code: Int

        // Check token-based routing first
        if let cookie = request.value(forHTTPHeaderField: "Cookie"),
           let serviceTokenRange = cookie.range(of: "api-platform_serviceToken=\"") {
            let afterQuote = cookie[serviceTokenRange.upperBound...]
            if let endQuote = afterQuote.range(of: "\"") {
                let tokenValue = String(afterQuote[..<endQuote.lowerBound])
                if let route = routeByToken[tokenValue] {
                    data = route.0.data(using: .utf8)!
                    code = route.1
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: code,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (data, response)
                }
            }
        }

        if !responseQueue.isEmpty {
            let entry = responseQueue.removeFirst()
            data = entry.0
            code = entry.1
        } else {
            data = responseData
            code = statusCode
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}
