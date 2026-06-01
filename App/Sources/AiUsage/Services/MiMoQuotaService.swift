import Foundation

struct AccountFetchResult: Sendable {
    let snapshot: EntitlementSummarySnapshot?
    let error: Error?
    let planUsed: Int
    let planLimit: Int
    let compensationUsed: Int
    let compensationLimit: Int
    let expiresAt: Date?
}

actor MiMoQuotaService {

    enum QuotaError: Error {
        case unauthorized
        case networkError(Error)
        case decodingError(Error)
        case serverError(code: Int, message: String)
    }

    private let client: MiMoHTTPClientProtocol

    init(client: MiMoHTTPClientProtocol) {
        self.client = client
    }

    func fetch(
        serviceToken: MiMoServiceToken,
        targetID: EntitlementTargetID,
        title: String,
        now: Date
    ) async throws -> EntitlementSummarySnapshot {
        let result = try await MiMoQuotaService.fetchFromAPI(
            client: client,
            serviceToken: serviceToken,
            targetID: targetID,
            title: title,
            now: now
        )
        return result.snapshot
    }

    func fetchAll(
        tokens: [UUID: MiMoServiceToken],
        targetID: EntitlementTargetID,
        title: String,
        now: Date
    ) async -> [UUID: AccountFetchResult] {
        guard !tokens.isEmpty else { return [:] }
        var results: [UUID: AccountFetchResult] = [:]
        for (accountID, token) in tokens {
            results[accountID] = await MiMoQuotaService.fetchSingle(
                client: client,
                serviceToken: token,
                targetID: targetID,
                title: title,
                now: now
            )
        }
        return results
    }

    private nonisolated static func fetchSingle(
        client: MiMoHTTPClientProtocol,
        serviceToken: MiMoServiceToken,
        targetID: EntitlementTargetID,
        title: String,
        now: Date
    ) async -> AccountFetchResult {
        do {
            let result = try await fetchFromAPI(
                client: client,
                serviceToken: serviceToken,
                targetID: targetID,
                title: title,
                now: now
            )
            return AccountFetchResult(
                snapshot: result.snapshot,
                error: nil,
                planUsed: result.planUsed,
                planLimit: result.planLimit,
                compensationUsed: result.compensationUsed,
                compensationLimit: result.compensationLimit,
                expiresAt: result.expiresAt
            )
        } catch {
            return AccountFetchResult(
                snapshot: nil,
                error: error,
                planUsed: 0,
                planLimit: 0,
                compensationUsed: 0,
                compensationLimit: 0,
                expiresAt: nil
            )
        }
    }

    private struct FetchAPIResult {
        let snapshot: EntitlementSummarySnapshot
        let planUsed: Int
        let planLimit: Int
        let compensationUsed: Int
        let compensationLimit: Int
        let expiresAt: Date?
    }

    private nonisolated static func fetchFromAPI(
        client: MiMoHTTPClientProtocol,
        serviceToken: MiMoServiceToken,
        targetID: EntitlementTargetID,
        title: String,
        now: Date
    ) async throws -> FetchAPIResult {
        let request = makeRequest(
            path: "/api/v1/tokenPlan/usage",
            serviceToken: serviceToken
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.execute(request)
        } catch {
            throw QuotaError.networkError(error)
        }

        if response.statusCode == 401 {
            throw QuotaError.unauthorized
        }

        let decoded: MiMoAPIResponse
        do {
            decoded = try JSONDecoder().decode(MiMoAPIResponse.self, from: data)
        } catch {
            throw QuotaError.decodingError(error)
        }

        guard decoded.code == 0 else {
            throw QuotaError.serverError(code: decoded.code, message: decoded.message ?? "")
        }

        guard let planItem = decoded.data.usage.items.first(where: { $0.name == "plan_total_token" }) else {
            throw QuotaError.decodingError(DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Missing plan_total_token"
            )))
        }
        let compensationItem = decoded.data.usage.items.first(where: { $0.name == "compensation_total_token" })

        let planUsed = planItem.used
        let planLimit = planItem.limit
        let compensationUsed = compensationItem?.used ?? 0
        let compensationLimit = compensationItem?.limit ?? 0
        let expiresAt: Date?
        if let usageExpiry = decoded.data.expiresAt {
            expiresAt = usageExpiry
        } else {
            expiresAt = await fetchDetailExpiry(client: client, serviceToken: serviceToken)
        }

        let primaryWindow = EntitlementWindowSnapshot(
            id: "\(targetID.storageKey)-mimo-primary",
            title: "套餐总额度",
            primaryText: percentageText(planItem.percent),
            secondaryText: tokenUsageText(used: planUsed, limit: planLimit),
            footnoteText: expiryText(expiresAt),
            progress: clampedProgress(planItem.percent)
        )

        let secondaryWindow: EntitlementWindowSnapshot
        if let compensationItem, compensationItem.limit > 0 {
            secondaryWindow = EntitlementWindowSnapshot(
                id: "\(targetID.storageKey)-mimo-compensation",
                title: "补偿额度",
                primaryText: percentageText(compensationItem.percent),
                secondaryText: tokenUsageText(used: compensationItem.used, limit: compensationItem.limit),
                footnoteText: expiryText(expiresAt),
                progress: clampedProgress(compensationItem.percent)
            )
        } else {
            secondaryWindow = .hidden(id: "\(targetID.storageKey)-mimo-compensation")
        }

        let snapshot = EntitlementSummarySnapshot(
            targetID: targetID,
            title: title,
            message: "",
            updatedAt: now,
            status: serviceToken.isExpired ? .stale : .ready,
            sourceKind: .mimo,
            provenance: .explicit,
            derivedFromTitle: nil,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )

        return FetchAPIResult(
            snapshot: snapshot,
            planUsed: planUsed,
            planLimit: planLimit,
            compensationUsed: compensationUsed,
            compensationLimit: compensationLimit,
            expiresAt: expiresAt
        )
    }

    private nonisolated static func percentageText(_ progress: Double) -> String {
        "已用 \(clampedProgress(progress).formatted(.percent.precision(.fractionLength(0))))"
    }

    private nonisolated static func tokenUsageText(used: Int, limit: Int) -> String {
        "\(tokenText(used)) / \(tokenText(limit)) token"
    }

    private nonisolated static func tokenText(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 100_000_000 {
            return "\(trimmed(Double(value) / 100_000_000))亿"
        }
        if absolute >= 10_000 {
            return "\(trimmed(Double(value) / 10_000))万"
        }
        return value.formatted()
    }

    private nonisolated static func trimmed(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private nonisolated static func expiryText(_ date: Date?) -> String {
        guard let date else { return "到期时间未返回" }
        return "到期 \(date.formatted(date: .numeric, time: .omitted))"
    }

    private nonisolated static func clampedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    private nonisolated static func makeRequest(
        path: String,
        serviceToken: MiMoServiceToken
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://platform.xiaomimimo.com\(path)")!)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://platform.xiaomimimo.com/console/plan-manage", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(serviceToken.cookieValue, forHTTPHeaderField: "Cookie")
        return request
    }

    private nonisolated static func fetchDetailExpiry(
        client: MiMoHTTPClientProtocol,
        serviceToken: MiMoServiceToken
    ) async -> Date? {
        let request = makeRequest(
            path: "/api/v1/tokenPlan/detail",
            serviceToken: serviceToken
        )
        guard let (data, response) = try? await client.execute(request),
              response.statusCode == 200 else { return nil }
        return MiMoExpiryFinder.find(in: data)
    }
}

// MARK: - Response Models

private struct MiMoAPIResponse: Decodable {
    let code: Int
    let message: String?
    let data: MiMoAPIData
}

private struct MiMoAPIData: Decodable {
    let expiresAt: Date?
    let monthUsage: MiMoUsageGroup
    let usage: MiMoUsageGroup

    enum CodingKeys: String, CodingKey {
        case expiresAt
        case expireAt
        case expiredAt
        case expireTime
        case expiredTime
        case endAt
        case endTime
        case endDate
        case validUntil
        case monthUsage
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expiresAt = Self.decodeDate(from: container)
        monthUsage = try container.decode(MiMoUsageGroup.self, forKey: .monthUsage)
        usage = try container.decode(MiMoUsageGroup.self, forKey: .usage)
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        for key in [
            CodingKeys.expiresAt,
            .expireAt,
            .expiredAt,
            .expireTime,
            .expiredTime,
            .endAt,
            .endTime,
            .endDate,
            .validUntil
        ] {
            if let string = try? container.decode(String.self, forKey: key),
               let date = parseDate(string) {
                return date
            }
            if let seconds = try? container.decode(Double.self, forKey: key) {
                return date(fromTimestamp: seconds)
            }
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func date(fromTimestamp value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
}

private struct MiMoUsageGroup: Decodable {
    let percent: Double
    let items: [MiMoUsageItem]
}

private struct MiMoUsageItem: Decodable {
    let name: String
    let used: Int
    let limit: Int
    let percent: Double
}

private enum MiMoExpiryFinder {
    private static let normalizedKeys = Set([
        "expiresAt",
        "expireAt",
        "expiredAt",
        "expireTime",
        "expiredTime",
        "endAt",
        "endTime",
        "endDate",
        "validUntil"
    ].map(normalizeKey)
    )

    static func find(in data: Data) -> Date? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return find(in: object)
    }

    private static func find(in object: Any) -> Date? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict where normalizedKeys.contains(normalizeKey(key)) {
                if let date = date(from: value) {
                    return date
                }
            }
            for value in dict.values {
                if let date = find(in: value) {
                    return date
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let date = find(in: value) {
                    return date
                }
            }
        }
        return nil
    }

    private static func normalizeKey(_ key: String) -> String {
        key.filter(\.isLetter).lowercased()
    }

    private static func date(from value: Any) -> Date? {
        if let string = value as? String {
            return parseDate(string)
        }
        if let seconds = value as? Double {
            return date(fromTimestamp: seconds)
        }
        if let seconds = value as? Int {
            return date(fromTimestamp: Double(seconds))
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func date(fromTimestamp value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
}
