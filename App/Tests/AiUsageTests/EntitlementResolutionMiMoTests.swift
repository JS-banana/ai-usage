import XCTest
import Domain
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
        XCTAssertEqual(summary.message, "")
        XCTAssertEqual(summary.visibleWindows.count, 1)
        XCTAssertEqual(summary.primaryWindow.primaryText, "需要重新登录小米账号")
        XCTAssertEqual(summary.primaryWindow.secondaryText, "")
        XCTAssertEqual(summary.primaryWindow.footnoteText, "")
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
        XCTAssertEqual(summary.message, "")
        XCTAssertEqual(summary.visibleWindows.count, 1)
        XCTAssertEqual(summary.primaryWindow.primaryText, "需要重新登录小米账号")
        XCTAssertEqual(summary.primaryWindow.secondaryText, "")
        XCTAssertEqual(summary.primaryWindow.footnoteText, "")
    }

    func testMiMoFallsBackToLatestSnapshotWhenQuotaUnauthorized() async {
        setupValidCredentials()
        setupFreshToken()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "MiMo",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 14,
                        limit: 100,
                        remaining: 86,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponse(statusCode: 401)

        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.primaryWindow.primaryText, "14% used")
        XCTAssertEqual(summary.menuBarProgress ?? 0, 0.14, accuracy: 0.001)
    }

    func testMiMoStartupUsesCachedSnapshotBeforeReadingLiveQuota() async {
        setupValidCredentials()
        setupFreshToken()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "MiMo",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 14,
                        limit: 100,
                        remaining: 86,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(
            for: descriptor,
            configuration: .mimoSelected,
            trigger: .startup,
            now: Date()
        )

        XCTAssertEqual(mockHTTP.quotaRequestCount, 0)
        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.primaryWindow.primaryText, "14% used")
        XCTAssertEqual(summary.menuBarProgress ?? 0, 0.14, accuracy: 0.001)
    }

    func testMiMoStartupFallbackIncludesCachedAccountSummariesForQuotaRows() async throws {
        setupValidCredentials()
        setupFreshToken()

        let aggregateAccountID = "mimo-aggregate"
        let aggregateSnapshot = makeCachedQuotaSnapshot(
            accountID: aggregateAccountID,
            used: 14,
            limit: 100
        )
        let accountSnapshot = makeCachedQuotaSnapshot(
            accountID: testAccountID.uuidString,
            used: 20,
            limit: 100,
            resetsAt: Date(timeIntervalSince1970: 1_782_575_999)
        )
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshotsByAccountID: [
                aggregateAccountID: aggregateSnapshot,
                testAccountID.uuidString: accountSnapshot
            ]
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: Set(["mimo"]),
            trigger: .startup,
            now: Date()
        )

        XCTAssertEqual(mockHTTP.quotaRequestCount, 0)
        XCTAssertEqual(summaries["mimo"]?.primaryWindow.primaryText, "20% used")

        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let accountSummary = try XCTUnwrap(summaries[accountKey])
        XCTAssertEqual(accountSummary.primaryWindow.title, "账号额度")
        XCTAssertEqual(accountSummary.primaryWindow.primaryText, "20% used")
        XCTAssertEqual(accountSummary.primaryWindow.detailText, "20 / 100 tokens")
        XCTAssertTrue(accountSummary.primaryWindow.secondaryText.hasPrefix("expires "))
    }

    func testMiMoStartupFallbackUsesCachedAccountLabelForPerAccountSummaryTitle() async throws {
        setupValidCredentials()
        setupFreshToken()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "ooo***k@gmail.com",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 14,
                        limit: 100,
                        remaining: 86,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let service = makeService(
            httpClient: MockMiMoFlowHTTPClient(),
            quotaSnapshotStore: snapshotStore
        )

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: Set(["mimo"]),
            trigger: .startup,
            now: Date()
        )

        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let accountSummary = try XCTUnwrap(summaries[accountKey])
        XCTAssertEqual(accountSummary.title, "ooo***k@gmail.com")
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
        XCTAssertEqual(summary.visibleWindows.count, 1)
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
        XCTAssertEqual(summary.primaryWindow.detailText, "")
        XCTAssertEqual(summary.primaryWindow.primaryText, "50% used")
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.5, accuracy: 0.01)
        XCTAssertFalse(summary.secondaryWindow.isVisible)
    }

    func testMiMoResolutionIncludesPerAccountSummariesForMenuBarPinning() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.quotaRouteByToken["tok1"] = (0.1, 0.2, 200)
        mockHTTP.quotaRouteByToken["tok2"] = (0.4, 0.6, 200)
        mockHTTP.profileByToken["tok1"] = (email: "user1@example.com", phone: "+86 111****1111")
        mockHTTP.profileByToken["tok2"] = (email: "user2@example.com", phone: "+86 222****2222")

        let service = makeService(httpClient: mockHTTP)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: ["mimo"],
            now: Date()
        )

        let firstKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let secondKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: secondAccountID)

        XCTAssertEqual(summaries["mimo"]?.status, .ready)
        XCTAssertEqual(summaries[firstKey]?.title, "user1@example.com")
        XCTAssertEqual(summaries[firstKey]?.sourceKind, .mimo)
        XCTAssertEqual(summaries[firstKey]?.menuBarProgress ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(summaries[secondKey]?.title, "user2@example.com")
        XCTAssertEqual(summaries[secondKey]?.menuBarProgress ?? 0, 0.6, accuracy: 0.001)
    }

    func testMiMoPerAccountSummaryKeepsUsageDetailAndExpiryForAccountRows() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.quotaRouteByToken["tok1"] = (0.1, 0.2, 200)
        mockHTTP.quotaRouteByToken["tok2"] = (0.4, 0.6, 200)

        let service = makeService(httpClient: mockHTTP)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: ["mimo"],
            now: Date()
        )

        let firstKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let firstSummary = try! XCTUnwrap(summaries[firstKey])
        XCTAssertEqual(firstSummary.primaryWindow.title, "账号额度")
        XCTAssertEqual(firstSummary.primaryWindow.primaryText, "20% used")
        XCTAssertEqual(firstSummary.primaryWindow.detailText, "200 / 1,000 tokens")
        XCTAssertEqual(firstSummary.primaryWindow.secondaryText, "expires 2026/6/27")
    }

    func testMiMoResolveSummariesReturnsCompactFailedAccountSummaryWhenTokenExistsButRefreshFails() async {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.quotaRouteByToken["cached_tok"] = (0.0, 0.0, 500)

        let service = makeService(httpClient: mockHTTP)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: ["mimo"],
            now: Date()
        )

        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let accountSummary = try! XCTUnwrap(summaries[accountKey])
        XCTAssertEqual(accountSummary.targetID, .provider("mimo"))
        XCTAssertEqual(accountSummary.title, "test")
        XCTAssertEqual(accountSummary.message, "套餐额度刷新失败。")
        XCTAssertNil(accountSummary.updatedAt)
        XCTAssertEqual(accountSummary.status, .failed)
        XCTAssertEqual(accountSummary.sourceKind, .mimo)
        XCTAssertEqual(accountSummary.provenance, .explicit)
        XCTAssertNil(accountSummary.derivedFromTitle)
        XCTAssertEqual(accountSummary.primaryWindow.title, "")
        XCTAssertEqual(accountSummary.primaryWindow.primaryText, "刷新失败")
        XCTAssertEqual(accountSummary.primaryWindow.secondaryText, "未知错误")
        XCTAssertEqual(accountSummary.primaryWindow.footnoteText, "")
        XCTAssertNil(accountSummary.primaryWindow.progress)
        XCTAssertFalse(accountSummary.secondaryWindow.isVisible)
    }

    func testMiMoResolutionPersistsProfileEmailAndPlanNameForAccountRows() async throws {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponseWithUsage(used: 100, limit: 200, monthPercent: 0.5)
        mockHTTP.planNameByToken["cached_tok"] = "Standard"
        mockHTTP.profileByToken["cached_tok"] = (
            email: "ooo***y@163.com",
            phone: "+86 150****8613"
        )

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        _ = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        let groups = QuotaAccountReadModel.makeGroups(entitlementsByTarget: [:], userDefaults: defaults)
        let account = try XCTUnwrap(groups.first?.accounts.first)
        XCTAssertEqual(account.title, "ooo***y@163.com")
        XCTAssertEqual(account.planName, "Standard")
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
        XCTAssertEqual(summary.primaryWindow.detailText, "")
        XCTAssertEqual(summary.primaryWindow.primaryText, "5% used")
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.055, accuracy: 0.001)
        XCTAssertEqual(summary.menuBarProgress ?? 0, 0.055, accuracy: 0.001)
        XCTAssertFalse(summary.secondaryWindow.isVisible)
    }

    func testMiMoDoesNotRequestOrShowPaidBalanceAcrossAccountsWhenPresent() async {
        setupTwoAccountsWithTokens()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.balanceRouteByToken["tok1"] = (100, 25, 125, "CNY")
        mockHTTP.balanceRouteByToken["tok2"] = (40, 35, 75, "CNY")
        mockHTTP.registerQuotaResponseWithUsage(used: 100, limit: 200, monthPercent: 0.5)
        mockHTTP.registerQuotaResponseWithUsage(used: 150, limit: 300, monthPercent: 0.5)

        let service = makeService(httpClient: mockHTTP)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(mockHTTP.balanceRequestCount, 0)
        XCTAssertNil(summary.visibleWindows.first { $0.title == "账户余额" })
    }

    func testDerivedOverviewDoesNotIncludeMiMoAccountBalanceWindow() async {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.balanceRouteByToken["cached_tok"] = (5, 5, 0, "CNY")
        mockHTTP.registerQuotaResponseWithUsage(used: 100, limit: 200, monthPercent: 0.5)

        let service = makeService(httpClient: mockHTTP)
        let descriptors = [
            EntitlementTargetDescriptor(targetID: .overview, name: "总览", supportsOfficial: false),
            mimoDescriptor()
        ]

        let summaries = await service.resolveSummaries(
            descriptors: descriptors,
            visibleProviderIDs: ["mimo"],
            now: Date()
        )

        let overview = summaries[EntitlementTargetID.overview.storageKey]
        XCTAssertEqual(mockHTTP.balanceRequestCount, 0)
        XCTAssertNil(overview?.visibleWindows.first { $0.title == "账户余额" })
    }

    func testDerivedOverviewCanUseMiMoEvenWhenMiMoIsNotAnAgentTab() async {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponseWithUsage(used: 100, limit: 200, monthPercent: 0.5)

        let service = makeService(httpClient: mockHTTP)
        let summaries = await service.resolveSummaries(
            descriptors: [
                EntitlementTargetDescriptor(targetID: .overview, name: "总览", supportsOfficial: false),
                mimoDescriptor()
            ],
            visibleProviderIDs: [],
            now: Date()
        )

        let overview = summaries[EntitlementTargetID.overview.storageKey]

        XCTAssertEqual(overview?.sourceKind, .mimo)
        XCTAssertEqual(overview?.derivedFromTitle, "MiMo")
        XCTAssertEqual(overview?.primaryWindow.primaryText, "50% used")
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

        // Account 1 succeeds, account 2 fails → keep usable data but mark it partial.
        XCTAssertEqual(summary.status, .stale)
        XCTAssertTrue(summary.message.contains("部分账号"))
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.5, accuracy: 0.01)
    }

    func testMiMoFallsBackToLatestSnapshotWhenQuotaRefreshFailsWithNetworkError() async {
        setupValidCredentials()
        setupFreshToken()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "MiMo",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 40,
                        limit: 100,
                        remaining: 60,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.primaryWindow.title, "账号额度")
        XCTAssertEqual(summary.primaryWindow.detailText, "40 / 100 tokens")
        XCTAssertEqual(summary.primaryWindow.primaryText, "40% used")
        XCTAssertEqual(summary.primaryWindow.progress ?? 0, 0.4, accuracy: 0.001)
    }

    func testMiMoFallsBackToLatestSnapshotWhenStoredTokenIsUnavailable() async {
        setupValidCredentials()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "MiMo",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 14,
                        limit: 100,
                        remaining: 86,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(mockHTTP.quotaRequestCount, 0)
        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.primaryWindow.primaryText, "14% used")
        XCTAssertEqual(summary.menuBarProgress ?? 0, 0.14, accuracy: 0.001)
    }

    func testSingleMiMoAccountStartupFallbackUsesAccountSnapshotInsteadOfAggregateSnapshot() async {
        setupValidCredentials()
        setupFreshToken()

        let aggregateSnapshot = makeCachedQuotaSnapshot(
            accountID: "mimo-aggregate",
            used: 14,
            limit: 100
        )
        let accountSnapshot = makeCachedQuotaSnapshot(
            accountID: testAccountID.uuidString,
            used: 29,
            limit: 100,
            resetsAt: Date(timeIntervalSince1970: 1_782_575_999)
        )
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshotsByAccountID: [
                "mimo-aggregate": aggregateSnapshot,
                testAccountID.uuidString: accountSnapshot
            ]
        )
        let service = makeService(httpClient: MockMiMoFlowHTTPClient(), quotaSnapshotStore: snapshotStore)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: Set(["mimo"]),
            trigger: .startup,
            now: Date()
        )

        XCTAssertEqual(summaries["mimo"]?.primaryWindow.primaryText, "29% used")
        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        XCTAssertEqual(summaries[accountKey]?.primaryWindow.primaryText, "29% used")
    }

    func testCachedMiMoSummaryFootnoteSaysItIsShowingCachedData() async throws {
        setupValidCredentials()
        setupFreshToken()

        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotStore = QuotaSnapshotStoreStub(
            snapshot: ProviderQuotaSnapshot(
                account: ProviderAccount(
                    id: testAccountID.uuidString,
                    providerID: "mimo",
                    accountLabel: "MiMo",
                    backendLabel: "xiaomi",
                    createdAt: capturedAt,
                    updatedAt: capturedAt
                ),
                snapshot: QuotaSnapshot(
                    id: "cached-snapshot",
                    accountID: testAccountID.uuidString,
                    refreshRunID: nil,
                    capturedAt: capturedAt,
                    freshnessDate: capturedAt,
                    isStale: false
                ),
                windows: [
                    AllowanceWindow(
                        id: "cached-window",
                        snapshotID: "cached-snapshot",
                        kind: .monthly,
                        used: 29,
                        limit: 100,
                        remaining: 71,
                        resetsAt: Date(timeIntervalSince1970: 2_000)
                    )
                ]
            )
        )
        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponse(statusCode: 401)
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)

        let summary = await service.resolveSummary(
            for: mimoDescriptor(),
            configuration: .mimoSelected,
            now: Date()
        )

        XCTAssertEqual(summary.status, .stale)
        XCTAssertTrue(summary.primaryWindow.footnoteText.hasPrefix("显示上次成功数据 · "))
        XCTAssertFalse(summary.primaryWindow.footnoteText.contains("上次成功刷新"))
    }

    func testMiMoPersistsAggregateSnapshotWhenAllAccountsRefresh() async {
        setupTwoAccountsWithTokens()

        let snapshotStore = QuotaSnapshotStoreStub(snapshot: nil)
        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.quotaRouteByToken["tok1"] = (0.2, 0.4, 200)
        mockHTTP.quotaRouteByToken["tok2"] = (0.2, 0.4, 200)

        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(snapshotStore.persistedSnapshots.count, 3)
        XCTAssertEqual(Set(snapshotStore.persistedSnapshots.map { $0.account.id }), [
            testAccountID.uuidString,
            secondAccountID.uuidString,
            "mimo-aggregate"
        ])
    }

    func testMiMoPersistsRealAccountSnapshotForSingleSuccessfulAccount() async throws {
        setupValidCredentials()
        setupFreshToken()

        let snapshotStore = QuotaSnapshotStoreStub(snapshot: nil)
        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponseWithUsage(
            planUsed: 2_050_000_000,
            planLimit: 11_000_000_000,
            compensationUsed: 0,
            compensationLimit: 3_290_000_000
        )
        mockHTTP.planNameByToken["cached_tok"] = "Standard"
        mockHTTP.profileByToken["cached_tok"] = (
            email: "ooo***y@163.com",
            phone: "+86 150****8613"
        )
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)

        let summary = await service.resolveSummary(
            for: mimoDescriptor(),
            configuration: .mimoSelected,
            now: now
        )

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(snapshotStore.persistedSnapshots.count, 1)
        let persisted = try XCTUnwrap(snapshotStore.persistedSnapshots.first)
        XCTAssertEqual(persisted.account.id, testAccountID.uuidString)
        XCTAssertEqual(persisted.account.providerID, "mimo")
        XCTAssertEqual(persisted.account.accountLabel, "ooo***y@163.com")
        XCTAssertEqual(persisted.account.backendLabel, "xiaomi")
        XCTAssertEqual(persisted.snapshot.capturedAt, now)
        XCTAssertEqual(persisted.snapshot.freshnessDate, now)
        let window = try XCTUnwrap(persisted.windows.first)
        XCTAssertEqual(window.used, 2_050_000_000)
        XCTAssertEqual(window.limit, 14_290_000_000)
        XCTAssertEqual(window.remaining, 12_240_000_000)
        XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 1_782_575_999))
    }

    func testPerAccountSummaryUsesProfileEmailAsTitleAfterRefresh() async throws {
        setupValidCredentials()
        setupFreshToken()

        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.registerQuotaResponseWithUsage(
            planUsed: 2_050_000_000,
            planLimit: 11_000_000_000,
            compensationUsed: 0,
            compensationLimit: 3_290_000_000
        )
        mockHTTP.planNameByToken["cached_tok"] = "Standard"
        mockHTTP.profileByToken["cached_tok"] = (
            email: "ooo***y@163.com",
            phone: "+86 150****8613"
        )
        let service = makeService(httpClient: mockHTTP)

        let summaries = await service.resolveSummaries(
            descriptors: [mimoDescriptor()],
            visibleProviderIDs: Set(["mimo"]),
            now: Date()
        )

        let accountKey = QuotaMenuBarTargetKey.account(providerID: "mimo", accountID: testAccountID)
        let accountSummary = try XCTUnwrap(summaries[accountKey])
        XCTAssertEqual(accountSummary.title, "ooo***y@163.com")
        XCTAssertEqual(accountSummary.primaryWindow.title, "账号额度")
        XCTAssertEqual(accountSummary.primaryWindow.detailText, "2.05B / 14.29B tokens")
        XCTAssertEqual(accountSummary.primaryWindow.primaryText, "14% used")
        XCTAssertEqual(accountSummary.primaryWindow.secondaryText, "expires 2026/6/27")
    }

    func testMiMoDoesNotPersistPartialAggregateWhenSomeAccountsFail() async {
        setupTwoAccountsWithTokens()

        let snapshotStore = QuotaSnapshotStoreStub(snapshot: nil)
        let mockHTTP = MockMiMoFlowHTTPClient()
        mockHTTP.quotaRouteByToken["tok1"] = (0.0, 0.0, 401)
        mockHTTP.quotaRouteByToken["tok2"] = (0.2, 0.4, 200)

        let service = makeService(httpClient: mockHTTP, quotaSnapshotStore: snapshotStore)
        let descriptor = mimoDescriptor()

        let summary = await service.resolveSummary(for: descriptor, configuration: .mimoSelected, now: Date())

        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(snapshotStore.persistedSnapshots.count, 1)
        XCTAssertEqual(snapshotStore.persistedSnapshots.first?.account.id, secondAccountID.uuidString)
        XCTAssertFalse(snapshotStore.persistedSnapshots.contains { $0.account.id == "mimo-aggregate" })
    }

    // MARK: - Helpers

    private func makeService(
        httpClient: MiMoHTTPClientProtocol = MockMiMoFlowHTTPClient(),
        quotaSnapshotStore: QuotaSnapshotStoring? = nil
    ) -> EntitlementResolutionService {
        let mimoQuota = MiMoQuotaService(client: httpClient)
        return EntitlementResolutionService(
            thirdPartyService: LaifuyouQuotaService(),
            officialProbe: OfficialEntitlementProbe(),
            mimoQuota: mimoQuota,
            quotaSnapshotStore: quotaSnapshotStore,
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

    private func makeCachedQuotaSnapshot(
        accountID: String,
        used: Double,
        limit: Double,
        resetsAt: Date? = nil
    ) -> ProviderQuotaSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let snapshotID = "cached-\(accountID)"
        return ProviderQuotaSnapshot(
            account: ProviderAccount(
                id: accountID,
                providerID: "mimo",
                accountLabel: "MiMo",
                backendLabel: "xiaomi",
                createdAt: capturedAt,
                updatedAt: capturedAt
            ),
            snapshot: QuotaSnapshot(
                id: snapshotID,
                accountID: accountID,
                refreshRunID: nil,
                capturedAt: capturedAt,
                freshnessDate: capturedAt,
                isStale: false
            ),
            windows: [
                AllowanceWindow(
                    id: "\(snapshotID)-window",
                    snapshotID: snapshotID,
                    kind: .monthly,
                    used: used,
                    limit: limit,
                    remaining: max(0, limit - used),
                    resetsAt: resetsAt
                )
            ]
        )
    }
}

private final class QuotaSnapshotStoreStub: QuotaSnapshotStoring, @unchecked Sendable {
    let snapshot: ProviderQuotaSnapshot?
    let snapshotsByAccountID: [String: ProviderQuotaSnapshot]
    private(set) var persistedSnapshots: [ProviderQuotaSnapshot] = []

    init(snapshot: ProviderQuotaSnapshot?) {
        self.snapshot = snapshot
        self.snapshotsByAccountID = [:]
    }

    init(snapshotsByAccountID: [String: ProviderQuotaSnapshot]) {
        self.snapshot = nil
        self.snapshotsByAccountID = snapshotsByAccountID
    }

    func persistQuotaSnapshot(_ snapshot: ProviderQuotaSnapshot) async throws {
        persistedSnapshots.append(snapshot)
    }

    func latestQuotaSnapshot(providerID: String, accountID: String) async throws -> ProviderQuotaSnapshot? {
        snapshotsByAccountID[accountID] ?? snapshot
    }
}

// MARK: - Mock HTTP Client for full MiMo flow

private final class MockMiMoFlowHTTPClient: MiMoHTTPClientProtocol, @unchecked Sendable {
    private var responses: [(URLRequest) -> (Data, HTTPURLResponse)] = []
    private(set) var ssoLoginCount = 0
    private(set) var quotaRequestCount = 0
    private(set) var balanceRequestCount = 0
    var quotaRouteByToken: [String: (Double, Double, Int)] = [:]  // serviceToken → (monthPercent, planPercent, statusCode)
    var balanceRouteByToken: [String: (balance: Double, gift: Double, cash: Double, currency: String)] = [:]
    var planNameByToken: [String: String] = [:]
    var profileByToken: [String: (email: String, phone: String)] = [:]

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
            let tokenValue = request.value(forHTTPHeaderField: "Cookie").flatMap(extractServiceToken(from:))
            let planName = tokenValue.flatMap { planNameByToken[$0] } ?? "Standard"
            let json = #"{"code":0,"data":{"planName":"\#(planName)","currentPeriodEnd":"2026-06-27 23:59:59"}}"#
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

        if request.url!.path.contains("userProfile") {
            let tokenValue = request.value(forHTTPHeaderField: "Cookie").flatMap(extractServiceToken(from:))
            let profile = tokenValue.flatMap { profileByToken[$0] } ?? ("user@example.com", "+86 000****0000")
            let json = #"{"code":0,"data":{"userId":"99","email":"\#(profile.email)","phone":"\#(profile.phone)","platformEmail":null,"nickName":null,"userName":null}}"#
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

        if request.url!.path.contains("balance") {
            balanceRequestCount += 1
        }

        if request.url!.path.contains("balance"),
           let cookie = request.value(forHTTPHeaderField: "Cookie"),
           let tokenValue = extractServiceToken(from: cookie),
           let route = balanceRouteByToken[tokenValue] {
            let json = """
            {"balance":"\(route.balance)","giftBalance":"\(route.gift)","cashBalance":"\(route.cash)","frozenBalance":"0","currency":"\(route.currency)"}
            """
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

        if request.url!.path.contains("balance") {
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
            let code = route.2 == 200 ? 0 : route.2
            let message = route.2 == 200 ? "" : "server error"
            let monthUsed = Int(route.0 * 1000)
            let planUsed = Int(route.1 * 1000)
            let json = """
            {"code":\(code),"message":"\(message)","data":{"monthUsage":{"percent":\(route.0),"items":[{"name":"month_total_token","used":\(monthUsed),"limit":1000,"percent":\(route.0)}]},"usage":{"percent":\(route.1),"items":[{"name":"plan_total_token","used":\(planUsed),"limit":1000,"percent":\(route.1)}]}}}
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
