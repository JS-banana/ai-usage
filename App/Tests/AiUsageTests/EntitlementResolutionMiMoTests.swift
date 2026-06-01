import XCTest
@testable import AiUsage

final class EntitlementResolutionMiMoTests: XCTestCase {

    private let suiteName = "EntitlementResolutionMiMoTests"
    private let testAccountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "entitlement.mimo.keychainNamespace")
        EntitlementPreferences.clearMiMoCredentials(userDefaults: defaults)
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: testAccountID, userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: secondAccountID, userDefaults: defaults)
    }

    override func tearDown() {
        EntitlementPreferences.clearMiMoCredentials(userDefaults: defaults)
        EntitlementPreferences.clearMiMoAccounts(userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: testAccountID, userDefaults: defaults)
        EntitlementPreferences.clearMiMoServiceToken(forAccount: secondAccountID, userDefaults: defaults)
        super.tearDown()
    }

    private let secondAccountID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: - Tests

    func testMiMoReturnsUnconfiguredWhenNoCredentials() async {
        let service = makeService()
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoUnconfigured, now: Date())

        XCTAssertEqual(summary.status, .unconfigured)
    }

    func testMiMoReturnsReadyWithFreshToken() async {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponse(monthPercent: 0.3, planPercent: 0.5)

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.5, accuracy: 0.01)
        XCTAssertFalse(summary.secondaryWindow.isVisible)
    }

    func testMiMoDoesNotAttemptHeadlessLoginWhenNoServiceToken() async {
        setupValidCredentials()
        // No service token stored

        let mockHTTP = MockMiMoFlowHTTPClient()

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(mockHTTP.ssoLoginCount, 0)
        XCTAssertEqual(mockHTTP.quotaRequestCount, 0)
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.sourceKind, .mimo)
        XCTAssertTrue(summary.secondaryWindow.primaryText.contains("重新登录"))
    }

    func testMiMoDoesNotAttemptHeadlessReloginOnQuotaUnauthorized() async {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponse(statusCode: 401)

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(mockHTTP.ssoLoginCount, 0)
        XCTAssertEqual(mockHTTP.quotaRequestCount, 1)
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.sourceKind, .mimo)
        XCTAssertTrue(summary.secondaryWindow.primaryText.contains("重新登录"))
    }

    func testMiMoReturnsFailedWhenNoStoredTokenExists() async {
        setupValidCredentials()

        let mockHTTP = MockMiMoFlowHTTPClient()

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(mockHTTP.ssoLoginCount, 0)
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.sourceKind, .mimo)
    }

    // MARK: - Multi-Account Tests

    func testMiMoResolvesMultipleAccounts() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponse(monthPercent: 0.3, planPercent: 0.5)
        mockHTTP.registerQuotaResponse(monthPercent: 0.4, planPercent: 0.6)

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        // Both accounts should have been queried (2 quota API calls)
        XCTAssertEqual(mockHTTP.quotaRequestCount, 2, "Expected both accounts to be queried")
    }

    func testMiMoAggregatesUsageAcrossAccounts() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        // Account 1: used=100, limit=200
        mockHTTP.registerQuotaResponseWithUsage(used: 100, limit: 200, monthPercent: 0.5)
        // Account 2: used=150, limit=300
        mockHTTP.registerQuotaResponseWithUsage(used: 150, limit: 300, monthPercent: 0.5)

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        // Aggregated plan: used=250, limit=500, progress = 250/500 = 0.5
        XCTAssertEqual(summary.sourceKind, .mimo)
        XCTAssertEqual(summary.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(summary.primaryWindow.primaryText, "已用 50%")
        XCTAssertTrue(summary.primaryWindow.secondaryText.contains("250"))
        XCTAssertTrue(summary.primaryWindow.secondaryText.contains("500"))
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.5, accuracy: 0.01)
        XCTAssertFalse(summary.secondaryWindow.isVisible)
    }

    func testMiMoAggregatesCompensationAcrossAccountsWhenPresent() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponseWithUsage(
            planUsed: 0,
            planLimit: 11_000_000_000,
            compensationUsed: 1_000_000_000,
            compensationLimit: 2_000_000_000
        )
        mockHTTP.registerQuotaResponseWithUsage(
            planUsed: 0,
            planLimit: 11_000_000_000,
            compensationUsed: 384_262_264,
            compensationLimit: 1_285_714_286
        )

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.primaryWindow.title, "套餐总额度")
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0, accuracy: 0.01)
        XCTAssertEqual(summary.secondaryWindow.title, "补偿额度")
        XCTAssertEqual(summary.secondaryWindow.primaryText, "已用 42%")
        XCTAssertTrue(summary.secondaryWindow.secondaryText.contains("13.84亿"))
        XCTAssertTrue(summary.secondaryWindow.secondaryText.contains("32.86亿"))
        XCTAssertTrue(summary.secondaryWindow.isVisible)
    }

    func testMiMoHandlesPartialLoginFailure() async {
        // Both accounts have tokens. One returns 401 and re-login also fails.
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        // tok1 → success
        mockHTTP.quotaRouteByToken["tok1"] = (0.3, 0.5, 200)
        // tok2 → 401, then re-login fails
        mockHTTP.quotaRouteByToken["tok2"] = (0.0, 0.0, 401)
        mockHTTP.registerSSOLoginFailure() // Re-login for account 2 fails

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        // Account 1 succeeds, account 2 fails → aggregated from successful accounts → ready
        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.5, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeService(httpClient: MiMoHTTPClientProtocol = MockMiMoFlowHTTPClient()) -> EntitlementResolutionService {
        let mimoQuota = MiMoQuotaService(client: httpClient)
        return EntitlementResolutionService(
            thirdPartyService: LaifuyouQuotaService(),
            officialProbe: OfficialEntitlementProbe(),
            mimoQuota: mimoQuota,
            userDefaults: defaults
        )
    }

    private func mimoDescriptor() -> EntitlementTargetDescriptor {
        EntitlementTargetDescriptor(targetID: .provider("mimo"), name: "MiMo", supportsOfficial: false)
    }

    private func setupValidCredentials() {
        let account = MiMoAccount(id: testAccountID, credentials: MiMoCredentials(username: "test", passwordMD5: "E10ADC3949BA59ABBE56E057F20F883E"))
        EntitlementPreferences.setMiMoAccounts([account], userDefaults: defaults)
    }

    private func setupFreshToken() {
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "cached_tok", userId: "99", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: testAccountID,
            userDefaults: defaults
        )
    }

    private func setupTwoAccountsWithTokens() {
        let account1 = MiMoAccount(id: testAccountID, credentials: MiMoCredentials(username: "user1", passwordMD5: "E10ADC3949BA59ABBE56E057F20F883E"))
        let account2 = MiMoAccount(id: secondAccountID, credentials: MiMoCredentials(username: "user2", passwordMD5: "E10ADC3949BA59ABBE56E057F20F883E"))
        EntitlementPreferences.setMiMoAccounts([account1, account2], userDefaults: defaults)

        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "tok1", userId: "u1", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: testAccountID,
            userDefaults: defaults
        )
        EntitlementPreferences.setMiMoServiceToken(
            MiMoServiceToken(serviceToken: "tok2", userId: "u2", slh: "s", ph: "p", acquiredAt: Date()),
            forAccount: secondAccountID,
            userDefaults: defaults
        )
    }
}

// MARK: - Mock HTTP Client for full MiMo flow

private final class MockMiMoFlowHTTPClient: MiMoHTTPClientProtocol, @unchecked Sendable {
    private var responses: [(URLRequest) -> (Data, HTTPURLResponse)] = []
    private(set) var ssoLoginCount = 0
    private(set) var quotaRequestCount = 0
    var quotaRouteByToken: [String: (Double, Double, Int)] = [:]  // serviceToken → (monthPercent, planPercent, statusCode)

    func registerSSOLogin() {
        // Step1: serviceLogin
        responses.append { req in
            let json = #"var _sign = 'abc'; var qs = 'q'; var callback = 'cb'; var sid = 'api-platform';"#
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // Step2: serviceLoginAuth2
        responses.append { req in
            let json = #"{"code":0,"userId":"88","passToken":"pt","ssecurity":"sec","location":"https://account.xiaomi.com/final?sid=api-platform"}"#
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // Step4: fetch serviceToken
        responses.append { req in
            let headers = ["Set-Cookie": "api-platform_serviceToken=new_tok; path=/, api-platform_slh=new_slh; path=/, api-platform_ph=new_ph; path=/"]
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        }
    }

    func registerSSOLoginFailure() {
        // Step1: OK
        responses.append { req in
            let json = #"var _sign = 'abc'; var qs = 'q'; var callback = 'cb'; var sid = 'api-platform';"#
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // Step2: auth failure
        responses.append { req in
            let json = #"{"code":70016,"description":"用户名或密码错误","result":"error"}"#
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func registerQuotaResponse(monthPercent: Double = 0.1, planPercent: Double = 0.1, statusCode: Int = 200) {
        responses.append { req in
            let monthUsed = Int(monthPercent * 1000)
            let planUsed = Int(planPercent * 1000)
            let json = """
            {"code":0,"data":{"monthUsage":{"percent":\(monthPercent),"items":[{"name":"month_total_token","used":\(monthUsed),"limit":1000,"percent":\(monthPercent)}]},"usage":{"percent":\(planPercent),"items":[{"name":"plan_total_token","used":\(planUsed),"limit":1000,"percent":\(planPercent)}]}}}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
    }

    func registerQuotaResponseWithUsage(used: Int, limit: Int, monthPercent: Double, statusCode: Int = 200) {
        responses.append { req in
            let json = """
            {"code":0,"data":{"monthUsage":{"percent":\(monthPercent),"items":[{"name":"month_total_token","used":\(used),"limit":\(limit),"percent":\(monthPercent)}]},"usage":{"percent":\(monthPercent),"items":[{"name":"plan_total_token","used":\(used),"limit":\(limit),"percent":\(monthPercent)}]}}}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
    }

    func registerQuotaResponseWithUsage(
        planUsed: Int,
        planLimit: Int,
        compensationUsed: Int,
        compensationLimit: Int,
        statusCode: Int = 200
    ) {
        responses.append { req in
            let planPercent = planLimit > 0 ? Double(planUsed) / Double(planLimit) : 0
            let compensationPercent = compensationLimit > 0 ? Double(compensationUsed) / Double(compensationLimit) : 0
            let json = """
            {"code":0,"data":{"monthUsage":{"percent":0,"items":[{"name":"month_total_token","used":0,"limit":0,"percent":0}]},"usage":{"percent":\(planPercent),"items":[{"name":"plan_total_token","used":\(planUsed),"limit":\(planLimit),"percent":\(planPercent)},{"name":"compensation_total_token","used":\(compensationUsed),"limit":\(compensationLimit),"percent":\(compensationPercent)}]}}}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: req.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Detect SSO login requests
        if request.url!.host == "account.xiaomi.com" {
            ssoLoginCount += 1
        }

        if request.url!.path.contains("tokenPlan/detail") {
            let json = #"{"code":0,"data":{}}"#
            return (
                json.data(using: .utf8)!,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        // Check token-based routing for quota requests
        if request.url!.path.contains("tokenPlan/usage") {
            quotaRequestCount += 1
        }
        if request.url!.path.contains("tokenPlan/usage"),
           let cookie = request.value(forHTTPHeaderField: "Cookie"),
           let tokenValue = extractServiceToken(from: cookie),
           let route = quotaRouteByToken[tokenValue] {
            let monthUsed = Int(route.0 * 1000)
            let planUsed = Int(route.1 * 1000)
            let json = """
            {"code":0,"data":{"monthUsage":{"percent":\(route.0),"items":[{"name":"month_total_token","used":\(monthUsed),"limit":1000,"percent":\(route.0)}]},"usage":{"percent":\(route.1),"items":[{"name":"plan_total_token","used":\(planUsed),"limit":1000,"percent":\(route.1)}]}}}
            """
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: route.2, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }

        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let handler = responses.removeFirst()
        return handler(request)
    }

    private func extractServiceToken(from cookie: String) -> String? {
        guard let range = cookie.range(of: "api-platform_serviceToken=\"") else { return nil }
        let afterQuote = cookie[range.upperBound...]
        guard let endQuote = afterQuote.range(of: "\"") else { return nil }
        return String(afterQuote[..<endQuote.lowerBound])
    }
}

// MARK: - Helpers

private extension EntitlementTargetConfiguration {
    static var mimoSelected: EntitlementTargetConfiguration {
        EntitlementTargetConfiguration(
            targetID: .provider("mimo"),
            selectedSource: .mimo,
            bridgeConfiguration: nil
        )
    }

    static var mimoUnconfigured: EntitlementTargetConfiguration {
        EntitlementTargetConfiguration(
            targetID: .provider("mimo"),
            selectedSource: .mimo,
            bridgeConfiguration: nil
        )
    }
}
