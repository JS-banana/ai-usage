import Foundation

struct MiMoWebCookie: Hashable, Sendable {
    let name: String
    let value: String
}

enum MiMoWebSessionExtractor {
    enum ExtractionError: Error, Equatable, LocalizedError {
        case missingCookies([String])

        var errorDescription: String? {
            switch self {
            case .missingCookies(let names):
                return "未获取到小米登录态: \(names.joined(separator: ", "))"
            }
        }
    }

    private static let requiredCookieNames = [
        "api-platform_serviceToken",
        "userId",
        "api-platform_slh",
        "api-platform_ph"
    ]

    static func extractToken(
        from cookies: [MiMoWebCookie],
        acquiredAt: Date = Date()
    ) throws -> MiMoServiceToken {
        let values = cookies.reduce(into: [String: String]()) { partial, cookie in
            let value = normalizedCookieValue(cookie.value)
            guard value.isEmpty == false else { return }
            partial[cookie.name] = value
        }

        let missing = requiredCookieNames.filter { values[$0] == nil }
        guard missing.isEmpty else {
            throw ExtractionError.missingCookies(missing)
        }

        return MiMoServiceToken(
            serviceToken: values["api-platform_serviceToken"]!,
            userId: values["userId"]!,
            slh: values["api-platform_slh"]!,
            ph: values["api-platform_ph"]!,
            acquiredAt: acquiredAt
        )
    }

    private static func normalizedCookieValue(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.first == "\"", value.last == "\"" {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
