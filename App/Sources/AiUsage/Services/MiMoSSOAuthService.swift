import Foundation
import CryptoKit

actor MiMoSSOAuthService {

    enum AuthError: Error, LocalizedError {
        case invalidCredentials
        case riskControl
        case networkError(step: Int, underlying: Error)
        case unexpectedResponse(detail: String)

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "用户名或密码错误"
            case .riskControl:
                return "触发风控，请稍后再试"
            case .networkError(let step, let underlying):
                return "网络错误(步骤\(step)): \(underlying.localizedDescription)"
            case .unexpectedResponse(let detail):
                return "服务器响应异常: \(detail)"
            }
        }
    }

    private let client: MiMoHTTPClientProtocol

    init(client: MiMoHTTPClientProtocol) {
        self.client = client
    }

    func login(credentials: MiMoCredentials) async throws -> MiMoServiceToken {
        // Step 1: GET serviceLogin to obtain sign, qs, callback, sid
        let step1Body: String
        do {
            var step1Request = URLRequest(url: URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=api-platform&_json=true")!)
            step1Request.httpMethod = "GET"
            let (data1, _) = try await client.execute(step1Request)
            step1Body = String(data: data1, encoding: .utf8) ?? ""
        } catch {
            throw AuthError.networkError(step: 1, underlying: error)
        }

        let step1JSON = Self.parseXiaomiPrefixedJSON(step1Body)
        let sign = step1JSON?["_sign"] as? String ?? ""
        let qs = step1JSON?["qs"] as? String ?? ""
        let callback = step1JSON?["callback"] as? String ?? ""
        let sid = step1JSON?["sid"] as? String ?? "api-platform"

        // Step 2: POST serviceLoginAuth2
        let bodyString = Self.formBody([
            ("sid", sid),
            ("_json", "true"),
            ("user", credentials.username),
            ("hash", credentials.passwordMD5),
            ("_sign", sign),
            ("qs", qs),
            ("callback", callback)
        ])
        var step2Request = URLRequest(url: URL(string: "https://account.xiaomi.com/pass/serviceLoginAuth2")!)
        step2Request.httpMethod = "POST"
        step2Request.httpBody = bodyString.data(using: .utf8)
        step2Request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let step2Data: Data
        do {
            let (data, _) = try await client.execute(step2Request)
            step2Data = data
        } catch {
            throw AuthError.networkError(step: 2, underlying: error)
        }

        guard let step2Body = String(data: step2Data, encoding: .utf8),
              let step2JSON = Self.parseXiaomiPrefixedJSON(step2Body) else {
            throw AuthError.unexpectedResponse(detail: "Step2 响应解析失败: \(String(data: step2Data, encoding: .utf8) ?? "<binary>")")
        }

        let code = step2JSON["code"] as? Int ?? -1
        if code != 0 {
            throw AuthError.invalidCredentials
        }

        guard let userId = step2JSON["userId"] as? String,
              let ssecurity = step2JSON["ssecurity"] as? String,
              let location = step2JSON["location"] as? String,
              !location.isEmpty, !ssecurity.isEmpty else {
            throw AuthError.riskControl
        }

        // Step 3: Generate clientSign = base64(sha1("nonce=<nonce>&<ssecurity>"))
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        let signInput = "nonce=\(nonce)&\(ssecurity)"
        let sha1 = Insecure.SHA1.hash(data: signInput.data(using: .utf8)!)
        let clientSign = Data(sha1).base64EncodedString()

        // Step 4: GET location with clientSign
        let separator = location.contains("?") ? "&" : "?"
        let step4URLString = "\(location)\(separator)clientSign=\(clientSign.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSign)"
        var step4Request = URLRequest(url: URL(string: step4URLString)!)
        step4Request.httpMethod = "GET"

        let step4Response: HTTPURLResponse
        do {
            let (_, response) = try await client.execute(step4Request)
            step4Response = response
        } catch {
            throw AuthError.networkError(step: 4, underlying: error)
        }

        // Parse Set-Cookie headers for serviceToken, slh, ph
        let cookies = Self.parseCookies(from: step4Response)

        guard let serviceToken = cookies["api-platform_serviceToken"], !serviceToken.isEmpty else {
            throw AuthError.unexpectedResponse(detail: "Step4 未获取到 serviceToken, cookies: \(cookies)")
        }

        return MiMoServiceToken(
            serviceToken: serviceToken,
            userId: userId,
            slh: cookies["api-platform_slh"] ?? "",
            ph: cookies["api-platform_ph"] ?? "",
            acquiredAt: Date()
        )
    }

    // MARK: - Helpers

    private static func parseXiaomiPrefixedJSON(_ body: String) -> [String: Any]? {
        let prefix = "&&&START&&&"
        let jsonBody: String
        if body.hasPrefix(prefix) {
            jsonBody = String(body.dropFirst(prefix.count))
        } else {
            jsonBody = body
        }
        guard let data = jsonBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func formBody(_ fields: [(String, String)]) -> String {
        fields
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func parseCookies(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: response.allHeaderFields.reduce(into: [:]) { partial, item in
                guard let key = item.key as? String, let value = item.value as? String else { return }
                partial[key] = value
            },
            for: response.url ?? URL(string: "https://account.xiaomi.com")!
        )
        for cookie in cookies {
            result[cookie.name] = cookie.value
        }
        return result
    }
}
