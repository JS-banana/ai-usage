import XCTest
import Domain
import Query
@testable import AiUsage

@MainActor
final class AppStateTests: XCTestCase {
    func testBootstrapFailureSurfacesStatusInsteadOfCrashing() async {
        let state = AppState(bootstrapError: BootstrapTestError.failed)

        XCTAssertEqual(state.statusMessage, "启动失败：示例故障")
        XCTAssertFalse(state.hasBootstrapped)

        await state.startIfNeeded()

        XCTAssertTrue(state.hasBootstrapped)
        XCTAssertEqual(state.statusMessage, "启动失败：示例故障")
    }

    func testStartupCancellationDoesNotSurfaceAsRefreshFailure() async {
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: CancelledImportRunnerStub(),
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: EmptyEntitlementResolverStub(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        await state.startIfNeeded()

        XCTAssertFalse(state.hasBootstrapped)
        XCTAssertEqual(state.statusMessage, "准备就绪")
    }

    func testAutoRefreshTimerCanBeStartedAndCancelled() async {
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: CancelledImportRunnerStub(),
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: EmptyEntitlementResolverStub(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        // Start auto-refresh with a very short interval for testing
        state.startAutoRefresh(intervalSeconds: 0.1)
        XCTAssertTrue(state.isAutoRefreshActive)

        // Cancel
        state.cancelAutoRefresh()
        XCTAssertFalse(state.isAutoRefreshActive)
    }

    func testAutoRefreshStartIsIdempotent() async throws {
        let importRunner = CountingImportRunnerStub()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: importRunner,
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: EmptyEntitlementResolverStub(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            ),
            refreshPolicy: RefreshPolicy(usageTTL: 0, entitlementTTL: 10_000, schedulerTick: 0.2)
        )
        state.lastEntitlementRefresh = Date()

        state.startAutoRefresh(intervalSeconds: 0.2)
        try await Task.sleep(for: .seconds(0.15))
        state.startAutoRefresh(intervalSeconds: 0.2)
        try await Task.sleep(for: .seconds(0.12))

        XCTAssertEqual(importRunner.runCount, 1)
        state.cancelAutoRefresh()
    }

    func testRefreshOnBecomeActiveDoesNotRefreshUsageOrEntitlements() async {
        let importRunner = CountingImportRunnerStub()
        let entitlementResolver = CountingEntitlementResolverStub()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: importRunner,
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: entitlementResolver,
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        await state.refreshOnBecomeActive()

        XCTAssertEqual(importRunner.runCount, 0)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 0)
    }

    func testRefreshIfStaleSeparatesUsageAndEntitlementTTL() async {
        let importRunner = CountingImportRunnerStub()
        let entitlementResolver = CountingEntitlementResolverStub()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: importRunner,
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: entitlementResolver,
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            ),
            refreshPolicy: RefreshPolicy(usageTTL: 600, entitlementTTL: 1800)
        )
        let now = Date(timeIntervalSince1970: 10_000)
        state.lastUsageRefresh = now.addingTimeInterval(-601)
        state.lastEntitlementRefresh = now.addingTimeInterval(-120)

        await state.refreshIfStale(now: now)

        XCTAssertEqual(importRunner.runCount, 1)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 0)
        XCTAssertNotNil(state.lastUsageRefresh)
        XCTAssertEqual(state.lastEntitlementRefresh, now.addingTimeInterval(-120))
    }

    func testRefreshCurrentEntitlementDoesNotRunUsageImport() async {
        let importRunner = CountingImportRunnerStub()
        let entitlementResolver = CountingEntitlementResolverStub()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: importRunner,
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: entitlementResolver,
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        await state.refreshCurrentEntitlement()

        XCTAssertEqual(importRunner.runCount, 0)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 1)
    }

    func testRefreshCurrentEntitlementCanRunWhileUsageRefreshIsSuspended() async {
        SuspendedImportRunnerStub.reset()
        let entitlementResolver = CountingEntitlementResolverStub()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: SuspendedImportRunnerStub(),
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: entitlementResolver,
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        let usageTask = Task {
            await state.refreshUsage(trigger: .background)
        }
        await SuspendedImportRunnerStub.waitUntilSuspended()

        let didRefreshEntitlement = await state.refreshCurrentEntitlement()

        XCTAssertTrue(didRefreshEntitlement)
        XCTAssertEqual(entitlementResolver.resolveCallCount, 1)
        XCTAssertEqual(state.usageRefreshState, .refreshing)

        SuspendedImportRunnerStub.resume()
        _ = await usageTask.value
    }

    func testMarkMiMoLoginCompletedAdvancesSequence() {
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: CancelledImportRunnerStub(),
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: EmptyEntitlementResolverStub(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        XCTAssertEqual(state.completedMiMoLoginSequence, 0)

        state.markMiMoLoginCompleted()

        XCTAssertEqual(state.completedMiMoLoginSequence, 1)
    }

    func testCancellingSuspendedRefreshClearsLoadingState() async {
        SuspendedImportRunnerStub.reset()
        let state = AppState(
            dataService: AppDataService(
                importCoordinator: SuspendedImportRunnerStub(),
                readModelService: EmptySnapshotReaderStub(),
                entitlementService: EmptyEntitlementResolverStub(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )

        let task = Task {
            await state.refresh()
        }
        await SuspendedImportRunnerStub.waitUntilSuspended()

        XCTAssertTrue(state.isLoading)
        XCTAssertEqual(state.statusMessage, "正在刷新数据…")

        task.cancel()
        await Task.yield()

        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.statusMessage, "准备就绪")

        SuspendedImportRunnerStub.resume()
        _ = await task.value
        XCTAssertEqual(state.statusMessage, "准备就绪")
    }
}

private enum BootstrapTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "示例故障"
    }
}

private struct CancelledImportRunnerStub: ImportRunning {
    func runImport(request: ImportRequest) async throws -> ImportResult {
        throw CancellationError()
    }
}

private final class CountingImportRunnerStub: ImportRunning, @unchecked Sendable {
    private(set) var runCount = 0

    func runImport(request: ImportRequest) async throws -> ImportResult {
        runCount += 1
        return ImportResult(
            run: ImportRun(
                id: "run-\(request.trigger.rawValue)",
                startedAt: request.startedAt,
                finishedAt: request.startedAt,
                status: .succeeded,
                trigger: request.trigger,
                totalFiles: 0,
                totalEvents: 0,
                totalSessions: 0,
                skippedRecords: 0
            ),
            sourceResults: []
        )
    }
}

private struct SuspendedImportRunnerStub: ImportRunning {
    private static let gate = SuspendedImportGate()

    func runImport(request: ImportRequest) async throws -> ImportResult {
        await Self.gate.wait(request: request)
    }

    static func resume() {
        gate.resume()
    }

    static func reset() {
        gate.reset()
    }

    static func waitUntilSuspended() async {
        await gate.waitUntilSuspended()
    }
}

private final class SuspendedImportGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ImportResult, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait(request: ImportRequest) async -> ImportResult {
        await withCheckedContinuation { continuation in
            let waiters: [CheckedContinuation<Void, Never>]
            lock.lock()
            self.continuation = continuation
            waiters = self.waiters
            self.waiters = []
            lock.unlock()
            waiters.forEach { $0.resume() }
        }
    }

    func resume() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: ImportResult(
            run: ImportRun(
                id: "run-1",
                startedAt: Date(),
                finishedAt: Date(),
                status: .succeeded,
                trigger: .manual,
                totalFiles: 0,
                totalEvents: 0,
                totalSessions: 0,
                skippedRecords: 0
            ),
            sourceResults: []
        ))
    }

    func reset() {
        lock.lock()
        continuation = nil
        waiters = []
        lock.unlock()
    }

    func waitUntilSuspended() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if self.continuation != nil {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

private struct EmptySnapshotReaderStub: AppSnapshotReading {
    func makeSnapshot(preferredTabID: String?) async throws -> AppSnapshot {
        AppSnapshot(
            providerTabs: [],
            providerPreferences: [],
            entitlementTargets: [],
            selectedTabID: EntitlementTargetID.overview.storageKey,
            overview: OverviewPanelSnapshot(
                todayTokens: 0,
                sevenDayTokens: 0,
                todayRequests: 0,
                sevenDayRequests: 0,
                cachedTokens: 0,
                activeSources: 0,
                trendPoints: [],
                providerRows: [],
                lastRefresh: Date()
            ),
            panelsByID: [:],
            lastRefresh: Date(),
            statusMessage: "Usage 已刷新"
        )
    }
}

private struct EmptyEntitlementResolverStub: EntitlementResolving {
    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        trigger: ImportTrigger,
        now: Date
    ) async -> [String: EntitlementSummarySnapshot] {
        [:]
    }
}

private final class CountingEntitlementResolverStub: EntitlementResolving, @unchecked Sendable {
    private(set) var resolveCallCount = 0

    func resolveSummaries(
        descriptors: [EntitlementTargetDescriptor],
        visibleProviderIDs: Set<String>,
        trigger: ImportTrigger,
        now: Date
    ) async -> [String: EntitlementSummarySnapshot] {
        resolveCallCount += 1
        return [:]
    }
}
