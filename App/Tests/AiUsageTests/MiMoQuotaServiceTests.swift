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
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "45% used")
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "")
        XCTAssertEqual(snapshot.primaryWindow.progress ?? 0, 0.4475, accuracy: 0.001)
        XCTAssertFalse(snapshot.secondaryWindow.isVisible)
        XCTAssertEqual(snapshot.sourceKind, .mimo)
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
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "10% used")
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "")
        XCTAssertEqual(snapshot.primaryWindow.progress ?? 0, 0.097, accuracy: 0.001)
        XCTAssertEqual(snapshot.menuBarProgress ?? 0, 0.097, accuracy: 0.001)
        XCTAssertFalse(snapshot.secondaryWindow.isVisible)
    }

    func testFetchDoesNotRequestOrShowAccountBalanceWhenBalanceEndpointExists() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"tokenPlan":{"expireTime":"2026-08-15 23:59:59"}}}"#
        let balanceJSON = """
        {
            "balance": "5.00",
            "frozenBalance": "0.00",
            "currency": "CNY",
            "overdraftLimit": "0.00",
            "remainingOverdraftLimit": "0.00",
            "giftBalance": "5.00",
            "cashBalance": "0.00"
        }
        """
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON, balanceJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertNil(snapshot.visibleWindows.first { $0.title == "账户余额" })
    }

    func testFetchFormatsMiMoCompactPlanAsUsedOnly() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"currentPeriodEnd":"2026-06-27 23:59:59"}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "50% used")
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "")
    }

    func testFetchFormatsMiMoGroupSummaryAsUsedOnly() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.29)
        let detailJSON = #"{"code":0,"data":{"currentPeriodEnd":"2026-06-27 23:59:59","planName":"Standard"}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
        XCTAssertEqual(snapshot.primaryWindow.primaryText, "50% used")
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "")
    }

    func testFetchDoesNotRequestBalanceWhenTokenPlanDetailFails() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([(usageJSON, 200), ("{}", 500)])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertNil(snapshot.visibleWindows.first { $0.title == "账户余额" })
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

        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
    }

    func testFetchUsesTokenPlanDetailExpiryWhenUsageHasNoExpiry() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"plan":{"expireAt":"2026-08-15T00:00:00+08:00"}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
    }

    func testFetchUsesTokenPlanDetailExpiryFromExpireTimeField() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"tokenPlan":{"expireTime":"2026-08-15 23:59:59"}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
    }

    func testFetchUsesTokenPlanDetailExpiryFromCurrentPeriodEndField() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"currentPeriodEnd":"2026-07-31T23:59:59+08:00","planCode":"mimo_api_pro","planName":"Pro"}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
    }

    func testFetchAllReturnsProfileEmailAndPlanNameForAccountDisplay() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.29)
        let detailJSON = #"{"code":0,"data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-06-27 23:59:59"}}"#
        let profileJSON = #"{"code":0,"data":{"userId":"897298966","phone":"+86 150****8613","email":"ooo***y@163.com","platformEmail":null,"nickName":null,"userName":null}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON, profileJSON])
        let service = MiMoQuotaService(client: mock)

        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let token = MiMoServiceToken(serviceToken: "tok", userId: "897298966", slh: "s", ph: "p", acquiredAt: Date())
        let results = await service.fetchAll(
            tokens: [accountID: token],
            targetID: .provider("mimo"),
            title: "MiMo",
            now: Date()
        )

        let result = try XCTUnwrap(results[accountID])
        XCTAssertEqual(result.profile?.email, "ooo***y@163.com")
        XCTAssertEqual(result.profile?.phone, "+86 150****8613")
        XCTAssertEqual(result.planName, "Standard")
        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail",
            "/api/v1/userProfile"
        ])
    }

    func testFetchAllReturnsMergedTotalsProfilePlanExpiryAndCapturedAt() async throws {
        let usageJSON = """
        {
            "code": 0,
            "data": {
                "monthUsage": {
                    "percent": 0,
                    "items": [{"name": "month_total_token", "used": 0, "limit": 0, "percent": 0}]
                },
                "usage": {
                    "percent": 0.143,
                    "items": [
                        {"name": "plan_total_token", "used": 2050000000, "limit": 11000000000, "percent": 0.18636},
                        {"name": "compensation_total_token", "used": 0, "limit": 3290000000, "percent": 0}
                    ]
                }
            }
        }
        """
        let detailJSON = #"{"code":0,"data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-06-27 23:59:59","expired":false}}"#
        let profileJSON = #"{"code":0,"data":{"userId":"897298966","phone":"+86 150****8613","email":"ooo***y@163.com","platformEmail":null,"nickName":null,"userName":null}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON, profileJSON])
        let service = MiMoQuotaService(client: mock)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let token = MiMoServiceToken(serviceToken: "tok", userId: "897298966", slh: "s", ph: "p", acquiredAt: now)

        let results = await service.fetchAll(
            tokens: [accountID: token],
            targetID: .provider("mimo"),
            title: "MiMo",
            now: now
        )

        let result = try XCTUnwrap(results[accountID])
        XCTAssertNil(result.error)
        XCTAssertEqual(result.totalUsed, 2_050_000_000)
        XCTAssertEqual(result.totalLimit, 14_290_000_000)
        XCTAssertEqual(result.expiresAt, Date(timeIntervalSince1970: 1_782_575_999))
        XCTAssertEqual(result.planName, "Standard")
        XCTAssertEqual(result.profile?.email, "ooo***y@163.com")
        XCTAssertEqual(result.profile?.phone, "+86 150****8613")
        XCTAssertEqual(result.capturedAt, now)
        XCTAssertEqual(result.snapshot?.primaryWindow.detailText, "2.05B / 14.29B tokens")
        XCTAssertEqual(result.snapshot?.primaryWindow.primaryText, "14% used")
        XCTAssertEqual(result.snapshot?.primaryWindow.secondaryText, "expires 2026/6/27")
        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail",
            "/api/v1/userProfile"
        ])
    }

    func testFetchUsesTokenPlanDetailExpiryFromSnakeCaseMillisecondTimestamp() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let detailJSON = #"{"code":0,"data":{"tokenPlan":{"expire_time":1786809599000}}}"#
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([usageJSON, detailJSON])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(mock.capturedRequests.map { $0.url?.path }, [
            "/api/v1/tokenPlan/usage",
            "/api/v1/tokenPlan/detail"
        ])
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
    }

    func testFetchKeepsUsageWhenTokenPlanDetailFails() async throws {
        let usageJSON = standardJSON(monthPercent: 0.1, planPercent: 0.2)
        let mock = MockQuotaHTTPClient(responseJSON: usageJSON)
        mock.enqueueResponses([(usageJSON, 200), ("{}", 500)])
        let service = MiMoQuotaService(client: mock)

        let token = MiMoServiceToken(serviceToken: "tok", userId: "u", slh: "s", ph: "p", acquiredAt: Date())
        let snapshot = try await service.fetch(serviceToken: token, targetID: .provider("mimo"), title: "MiMo", now: Date())

        XCTAssertEqual(snapshot.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(snapshot.primaryWindow.secondaryText, "")
        XCTAssertEqual(snapshot.primaryWindow.detailText, "")
        XCTAssertEqual(snapshot.primaryWindow.footnoteText, "")
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
