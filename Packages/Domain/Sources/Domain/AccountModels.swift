import Foundation

public enum DataDomain: String, Hashable, Sendable {
    case usageFacts
    case accountQuotaSnapshots
}

public enum AllowanceWindowKind: String, Hashable, Sendable {
    case rollingFiveHours
    case daily
    case weekly
    case monthly
    case balance
}

public enum AccountRefreshStatus: String, Hashable, Sendable {
    case running
    case succeeded
    case failed
    case partial
}

public enum AccountDiagnosticSeverity: String, Hashable, Sendable {
    case info
    case warning
    case error
}

public struct ProviderAccount: Identifiable, Hashable, Sendable {
    public let id: String
    public let providerID: String
    public let accountLabel: String
    public let backendLabel: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, providerID: String, accountLabel: String, backendLabel: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.providerID = providerID
        self.accountLabel = accountLabel
        self.backendLabel = backendLabel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AccountRefreshRun: Identifiable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: AccountRefreshStatus
    public let diagnosticsCount: Int

    public init(id: String, accountID: String, startedAt: Date, finishedAt: Date? = nil, status: AccountRefreshStatus, diagnosticsCount: Int = 0) {
        self.id = id
        self.accountID = accountID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.diagnosticsCount = max(0, diagnosticsCount)
    }
}

public struct QuotaSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let refreshRunID: String?
    public let capturedAt: Date
    public let freshnessDate: Date
    public let isStale: Bool

    public init(id: String, accountID: String, refreshRunID: String? = nil, capturedAt: Date, freshnessDate: Date, isStale: Bool) {
        self.id = id
        self.accountID = accountID
        self.refreshRunID = refreshRunID
        self.capturedAt = capturedAt
        self.freshnessDate = freshnessDate
        self.isStale = isStale
    }
}

public struct AllowanceWindow: Identifiable, Hashable, Sendable {
    public let id: String
    public let snapshotID: String
    public let kind: AllowanceWindowKind
    public let used: Double
    public let limit: Double?
    public let remaining: Double?
    public let resetsAt: Date?

    public init(id: String, snapshotID: String, kind: AllowanceWindowKind, used: Double, limit: Double?, remaining: Double?, resetsAt: Date?) {
        self.id = id
        self.snapshotID = snapshotID
        self.kind = kind
        self.used = max(0, used)
        self.limit = limit.map { max(0, $0) }
        self.remaining = remaining.map { max(0, $0) }
        self.resetsAt = resetsAt
    }
}

public struct AccountDiagnostic: Identifiable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let snapshotID: String?
    public let severity: AccountDiagnosticSeverity
    public let message: String
    public let createdAt: Date

    public init(id: String, accountID: String, snapshotID: String? = nil, severity: AccountDiagnosticSeverity, message: String, createdAt: Date) {
        self.id = id
        self.accountID = accountID
        self.snapshotID = snapshotID
        self.severity = severity
        self.message = message
        self.createdAt = createdAt
    }
}
