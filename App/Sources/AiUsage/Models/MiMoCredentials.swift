import Foundation

struct MiMoCredentials: Hashable, Sendable, Codable {
    let username: String
    let passwordMD5: String
}

struct MiMoAccount: Identifiable, Sendable, Codable {
    let id: UUID
    let credentials: MiMoCredentials
    let displayName: String

    init(id: UUID = UUID(), credentials: MiMoCredentials, displayName: String? = nil) {
        self.id = id
        self.credentials = credentials
        self.displayName = displayName ?? credentials.username
    }
}

extension MiMoAccount: Hashable {
    static func == (lhs: MiMoAccount, rhs: MiMoAccount) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MiMoServiceToken: Hashable, Sendable, Codable {
    let serviceToken: String
    let userId: String
    let slh: String
    let ph: String
    let acquiredAt: Date

    var isExpired: Bool { false }

    var cookieValue: String {
        "api-platform_serviceToken=\"\(serviceToken.normalizedCookieComponent)\"; userId=\(userId.normalizedCookieComponent); api-platform_slh=\"\(slh.normalizedCookieComponent)\"; api-platform_ph=\"\(ph.normalizedCookieComponent)\""
    }
}

private extension String {
    var normalizedCookieComponent: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.first == "\"", value.last == "\"" {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
