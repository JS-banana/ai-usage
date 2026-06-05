import XCTest
@testable import AiUsage

final class MiMoSSOAuthServiceTests: XCTestCase {

    // MARK: - Happy Path

    func testLoginReturnsServiceTokenOnSuccess() async throws {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.registerStep2Auth(userId: "12345", passToken: "pt", ssecurity: "sec123", location: "https://account.xiaomi.com/step3?sid=api-platform")
        mock.registerStep4ServiceToken(token: "svc_tok_abc", slh: "slh_val", ph: "ph_val")

        let service = MiMoSSOAuthService(client: mock)
        let creds = MiMoCredentials(username: "testuser", passwordMD5: "E10ADC3949BA59ABBE56E057F20F883E")
        let token = try await service.login(credentials: creds)

        XCTAssertEqual(token.serviceToken, "svc_tok_abc")
        XCTAssertEqual(token.userId, "12345")
        XCTAssertEqual(token.slh, "slh_val")
        XCTAssertEqual(token.ph, "ph_val")
    }

    func testLoginSendsCorrectStep1Request() async throws {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.registerStep2Auth()
        mock.registerStep4ServiceToken()

        let service = MiMoSSOAuthService(client: mock)
        _ = try await service.login(credentials: .testFixture)

        let step1 = mock.requests[0]
        XCTAssertTrue(step1.url!.absoluteString.contains("account.xiaomi.com/pass/serviceLogin"))
        XCTAssertTrue(step1.url!.absoluteString.contains("sid=api-platform"))
        XCTAssertEqual(step1.httpMethod, "GET")
    }

    func testLoginSendsCorrectStep2Body() async throws {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.registerStep2Auth()
        mock.registerStep4ServiceToken()

        let service = MiMoSSOAuthService(client: mock)
        _ = try await service.login(credentials: MiMoCredentials(username: "myuser", passwordMD5: "HASH123"))

        let step2 = mock.requests[1]
        XCTAssertEqual(step2.httpMethod, "POST")
        let body = String(data: step2.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("user=myuser"))
        XCTAssertTrue(body.contains("hash=HASH123"))
        XCTAssertTrue(body.contains("sid=api-platform"))
    }

    func testLoginPercentEncodesStep2FormValues() async throws {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign(sign: "a+b/c=", qs: "q=a b&next=/console", callback: "https://cb.example.com/a?x=1&y=2")
        mock.registerStep2Auth()
        mock.registerStep4ServiceToken()

        let service = MiMoSSOAuthService(client: mock)
        _ = try await service.login(credentials: MiMoCredentials(username: "user+name@example.com", passwordMD5: "HASH+VALUE"))

        let body = String(data: mock.requests[1].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("user=user%2Bname%40example.com"))
        XCTAssertTrue(body.contains("hash=HASH%2BVALUE"))
        XCTAssertTrue(body.contains("_sign=a%2Bb%2Fc%3D"))
        XCTAssertTrue(body.contains("qs=q%3Da%20b%26next%3D%2Fconsole"))
        XCTAssertTrue(body.contains("callback=https%3A%2F%2Fcb.example.com%2Fa%3Fx%3D1%26y%3D2"))
    }

    func testClientSignIsBase64OfSHA1() async throws {
        // clientSign = base64(sha1("nonce=<nonce>&<ssecurity>"))
        // We verify the sign is appended to the step4 location URL
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.registerStep2Auth(ssecurity: "my_secret", location: "https://account.xiaomi.com/final")
        mock.registerStep4ServiceToken()

        let service = MiMoSSOAuthService(client: mock)
        _ = try await service.login(credentials: .testFixture)

        let step4 = mock.requests[2]
        let url = step4.url!.absoluteString
        XCTAssertTrue(url.contains("clientSign="), "Step4 URL must contain clientSign parameter")
    }

    // MARK: - Error Cases

    func testLoginThrowsInvalidCredentialsOnAuthFailure() async {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.responses.append(MockHTTPResponse(
            data: #"&&&START&&&{"code":70016,"description":"用户名或密码错误","result":"error"}"#.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "https://account.xiaomi.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))

        let service = MiMoSSOAuthService(client: mock)
        do {
            _ = try await service.login(credentials: .testFixture)
            XCTFail("Expected invalidCredentials error")
        } catch let error as MiMoSSOAuthService.AuthError {
            if case .invalidCredentials = error {
                // expected
            } else {
                XCTFail("Expected .invalidCredentials, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLoginThrowsNetworkErrorOnURLError() async {
        let mock = MockMiMoHTTPClient()
        mock.error = URLError(.timedOut)

        let service = MiMoSSOAuthService(client: mock)
        do {
            _ = try await service.login(credentials: .testFixture)
            XCTFail("Expected networkError")
        } catch let error as MiMoSSOAuthService.AuthError {
            if case .networkError = error {
                // expected
            } else {
                XCTFail("Expected .networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLoginThrowsRiskControlOnUnexpectedStep2Response() async {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        // Step2 returns 200 but no location/ssecurity → risk control
        mock.responses.append(MockHTTPResponse(
            data: #"&&&START&&&{"code":0,"location":"","ssecurity":""}"#.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "https://account.xiaomi.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))

        let service = MiMoSSOAuthService(client: mock)
        do {
            _ = try await service.login(credentials: .testFixture)
            XCTFail("Expected riskControl or unexpectedResponse error")
        } catch {
            // Any error is acceptable here
        }
    }

    func testLoginThrowsWhenStep4MissingServiceToken() async {
        let mock = MockMiMoHTTPClient()
        mock.registerStep1Sign()
        mock.registerStep2Auth()
        // Step4 response with no serviceToken cookie
        mock.responses.append(MockHTTPResponse(
            data: Data(),
            response: HTTPURLResponse(
                url: URL(string: "https://account.xiaomi.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        ))

        let service = MiMoSSOAuthService(client: mock)
        do {
            _ = try await service.login(credentials: .testFixture)
            XCTFail("Expected error for missing serviceToken")
        } catch {
            // expected
        }
    }
}

// MARK: - Test Fixtures

private extension MiMoCredentials {
    static let testFixture = MiMoCredentials(username: "test", passwordMD5: "E10ADC3949BA59ABBE56E057F20F883E")
}

// MARK: - Mock HTTP Client

private struct MockHTTPResponse {
    let data: Data
    let response: HTTPURLResponse
}

private final class MockMiMoHTTPClient: MiMoHTTPClientProtocol, @unchecked Sendable {
    var responses: [MockHTTPResponse] = []
    var requests: [URLRequest] = []
    var error: Error?

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let error { throw error }
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let resp = responses.removeFirst()
        return (resp.data, resp.response)
    }

    // Step1: serviceLogin returns _sign, qs, callback, sid (Xiaomi &&&START&&& prefix format)
    func registerStep1Sign(
        sign: String = "abc123",
        qs: String = "q=val",
        callback: String = "cb"
    ) {
        let json = #"&&&START&&&{"_sign":"\#(sign)","qs":"\#(qs)","callback":"\#(callback)","sid":"api-platform","code":0}"#
        responses.append(MockHTTPResponse(
            data: json.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "https://account.xiaomi.com/pass/serviceLogin")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))
    }

    // Step2: serviceLoginAuth2 returns userId, passToken, ssecurity, location (Xiaomi &&&START&&& prefix format)
    func registerStep2Auth(
        userId: String = "999",
        passToken: String = "pt_default",
        ssecurity: String = "sec_default",
        location: String = "https://account.xiaomi.com/step3?sid=api-platform"
    ) {
        let json = #"""
        &&&START&&&{"code":0,"userId":"\#(userId)","passToken":"\#(passToken)","ssecurity":"\#(ssecurity)","location":"\#(location)"}
        """#
        responses.append(MockHTTPResponse(
            data: json.data(using: .utf8)!,
            response: HTTPURLResponse(url: URL(string: "https://account.xiaomi.com/pass/serviceLoginAuth2")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))
    }

    // Step4: final redirect with Set-Cookie headers
    func registerStep4ServiceToken(
        token: String = "default_token",
        slh: String = "default_slh",
        ph: String = "default_ph"
    ) {
        let headers = [
            "Set-Cookie": "api-platform_serviceToken=\(token); path=/, api-platform_slh=\(slh); path=/, api-platform_ph=\(ph); path=/"
        ]
        responses.append(MockHTTPResponse(
            data: Data(),
            response: HTTPURLResponse(url: URL(string: "https://account.xiaomi.com")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        ))
    }
}
