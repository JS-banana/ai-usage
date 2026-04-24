import Foundation
import Support

struct LaifuyouQuotaConfiguration {
    static let apiKeyDefaultsKey = "quota.laifuyou.apiKey"
    static let endpointURLDefaultsKey = "quota.laifuyou.endpointURL"
    static let legacyGroupIDDefaultsKey = "quota.laifuyou.groupID"
    static let legacyBaseURL = URL(string: "https://quota.laifuyou.com")!

    let apiKey: String
    let endpointURL: URL

    static func current(userDefaults: UserDefaults = .standard) -> LaifuyouQuotaConfiguration? {
        let apiKey = (userDefaults.string(forKey: apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else { return nil }

        if let endpointURL = configuredEndpointURL(userDefaults: userDefaults) {
            return LaifuyouQuotaConfiguration(apiKey: apiKey, endpointURL: endpointURL)
        }

        if let legacyURL = legacyEndpointURL(userDefaults: userDefaults) {
            return LaifuyouQuotaConfiguration(apiKey: apiKey, endpointURL: legacyURL)
        }

        return nil
    }

    private static func configuredEndpointURL(userDefaults: UserDefaults) -> URL? {
        let rawValue = (userDefaults.string(forKey: endpointURLDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawValue.isEmpty == false else { return nil }
        return normalizedURL(from: rawValue)
    }

    private static func legacyEndpointURL(userDefaults: UserDefaults) -> URL? {
        let groupValue = (userDefaults.string(forKey: legacyGroupIDDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard groupValue.isEmpty == false else { return nil }
        var components = URLComponents(url: legacyBaseURL.appendingPathComponent("quota-summary"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "group_id", value: groupValue)]
        return components?.url
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        return URL(string: "https://\(rawValue)")
    }
}

struct LaifuyouQuotaWindowPayload: Sendable {
    let id: String
    let title: String
    let used: Double
    let limit: Double?
    let remaining: Double?
    let nextResetAt: Date?
    let progress: Double?
}

struct LaifuyouQuotaPayload: Sendable {
    let groupID: Int
    let groupName: String
    let updatedAt: Date
    let isStale: Bool
    let fiveHour: LaifuyouQuotaWindowPayload
    let weekly: LaifuyouQuotaWindowPayload
}

actor LaifuyouQuotaService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let userDefaults: UserDefaults

    init(session: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.session = session
        self.userDefaults = userDefaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = DateParsing.parseISO8601(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        self.decoder = decoder
    }

    func fetchIfConfigured(now: Date = Date()) async throws -> LaifuyouQuotaPayload? {
        guard let configuration = LaifuyouQuotaConfiguration.current(userDefaults: userDefaults) else {
            return nil
        }

        let response = try await fetchSummary(configuration: configuration)
        return mapResponse(response, now: now)
    }

    private func fetchSummary(configuration: LaifuyouQuotaConfiguration) async throws -> LaifuyouQuotaSummaryResponse {
        guard configuration.endpointURL.scheme?.isEmpty == false else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw QuotaServiceError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(LaifuyouQuotaSummaryResponse.self, from: data)
    }

    private func mapResponse(_ response: LaifuyouQuotaSummaryResponse, now: Date) -> LaifuyouQuotaPayload {
        LaifuyouQuotaPayload(
            groupID: response.groupID,
            groupName: response.group.name,
            updatedAt: response.updatedAt,
            isStale: now.timeIntervalSince(response.updatedAt) > 1800,
            fiveHour: makeWindowPayload(id: "quota-5h", title: "5h", window: response.quota5h),
            weekly: makeWindowPayload(id: "quota-7d", title: "周", window: response.quota7d)
        )
    }

    private func makeWindowPayload(id: String, title: String, window: LaifuyouQuotaSummaryResponse.QuotaWindow) -> LaifuyouQuotaWindowPayload {
        let progress = window.capacityUnits > 0 ? min(max(window.usedUnits / window.capacityUnits, 0), 1) : nil
        return LaifuyouQuotaWindowPayload(
            id: id,
            title: title,
            used: window.usedUnits,
            limit: window.capacityUnits,
            remaining: window.remainingUnits,
            nextResetAt: window.nextResetAt,
            progress: progress
        )
    }
}

enum QuotaServiceError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Quota 服务返回状态码 \(statusCode)"
        }
    }
}

private struct LaifuyouQuotaSummaryResponse: Decodable {
    struct Group: Decodable {
        let id: Int
        let name: String
    }

    struct QuotaWindow: Decodable {
        let capacityUnits: Double
        let usedUnits: Double
        let remainingUnits: Double
        let remainingPercent: Double
        let nextResetAt: Date?
        let latestResetAt: Date?

        enum CodingKeys: String, CodingKey {
            case capacityUnits = "capacity_units"
            case usedUnits = "used_units"
            case remainingUnits = "remaining_units"
            case remainingPercent = "remaining_percent"
            case nextResetAt = "next_reset_at"
            case latestResetAt = "latest_reset_at"
        }
    }

    let group: Group
    let groupID: Int
    let quota5h: QuotaWindow
    let quota7d: QuotaWindow
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case group
        case groupID = "group_id"
        case quota5h = "quota_5h"
        case quota7d = "quota_7d"
        case updatedAt = "updated_at"
    }
}
