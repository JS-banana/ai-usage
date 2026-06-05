import Foundation

protocol MiMoHTTPClientProtocol: Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: MiMoHTTPClientProtocol {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
