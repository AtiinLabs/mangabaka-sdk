import CryptoKit
import Foundation
@testable import MangaBakaSDK
import Testing

internal struct OAuthTests {
    private static let issued = Date(timeIntervalSince1970: 1_800_000_000)

    /// Records token requests and answers each with the next canned response.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [(Int, String)]
        private var recorded: [URLRequest] = []

        init(_ responses: [(Int, String)]) {
            self.responses = responses
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func handle(_ request: URLRequest) -> (Data, URLResponse) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(request)
            let (status, body) = responses.isEmpty ? (500, "{}") : responses.removeFirst()
            let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
            return (Data(body.utf8), response ?? URLResponse())
        }
    }

    private func oauth(_ server: Server) -> MangaBakaOAuth {
        MangaBakaOAuth(
            clientID: "client-1",
            redirectURI: "ito://mangabaka-callback",
            now: { Self.issued },
            send: { request in server.handle(request) }
        )
    }

    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let items = URLComponents(string: "https://example.invalid/?\(body)")?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test
    internal func authorizationRequestUsesS256AndTheRegisteredRedirect() throws {
        let request = oauth(Server([])).authorizationRequest()

        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        let digest = Data(SHA256.hash(data: Data(request.codeVerifier.utf8))).base64EncodedString()
        let expectedChallenge = digest
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(request.url.absoluteString.hasPrefix("https://mangabaka.org/auth/oauth2/authorize?"))
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "client-1")
        #expect(query["redirect_uri"] == "ito://mangabaka-callback")
        #expect(query["scope"] == "library.read library.write offline_access")
        #expect(query["state"] == request.state)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == expectedChallenge)
        #expect((43...128).contains(request.codeVerifier.count))
        #expect(oauth(Server([])).authorizationRequest().state != request.state)
    }

    @Test
    internal func callbackChecksStateAndReportsErrors() throws {
        let client = oauth(Server([]))
        let request = client.authorizationRequest()
        func callback(_ query: String) -> URL {
            URL(string: "ito://mangabaka-callback?\(query)") ?? URL(fileURLWithPath: "/")
        }

        #expect(try client.authorizationCode(from: callback("code=abc&state=\(request.state)"), matching: request) == "abc")
        #expect(throws: MangaBakaOAuthError.stateMismatch) {
            try client.authorizationCode(from: callback("code=abc&state=other"), matching: request)
        }
        #expect(throws: MangaBakaOAuthError.missingCode) {
            try client.authorizationCode(from: callback("state=\(request.state)"), matching: request)
        }
        #expect(throws: MangaBakaOAuthError.authorizationFailed(error: "access_denied", description: "User denied")) {
            try client.authorizationCode(from: callback("error=access_denied&error_description=User%20denied&state=\(request.state)"), matching: request)
        }
    }

    @Test
    internal func exchangeSendsTheVerifierWithoutASecret() async throws {
        let server = Server([(200, #"{"access_token":"access-1","token_type":"Bearer","expires_in":3600,"refresh_token":"refresh-1","scope":"library.read library.write offline_access"}"#)])
        let client = oauth(server)
        let request = client.authorizationRequest()

        let token = try await client.exchangeCode("code-1", for: request)

        #expect(token == MangaBakaToken(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Self.issued.addingTimeInterval(3600),
            scope: "library.read library.write offline_access"
        ))
        let sent = try #require(server.requests.first)
        #expect(sent.url?.absoluteString == "https://mangabaka.org/auth/oauth2/token")
        #expect(sent.httpMethod == "POST")
        #expect(form(sent) == [
            "client_id": "client-1",
            "grant_type": "authorization_code",
            "code": "code-1",
            "redirect_uri": "ito://mangabaka-callback",
            "code_verifier": request.codeVerifier
        ])
    }

    @Test
    internal func refreshKeepsTheOldRefreshTokenWhenNoneIsReturned() async throws {
        let server = Server([
            (200, #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":60}"#),
            (200, #"{"access_token":"access-3"}"#)
        ])
        let client = oauth(server)
        let original = MangaBakaToken(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: nil, scope: nil)

        let rotated = try await client.refresh(original)
        let kept = try await client.refresh(rotated)

        #expect(rotated.refreshToken == "refresh-2")
        #expect(kept.refreshToken == "refresh-2")
        #expect(kept.expiresAt == nil)
        #expect(server.requests.map { form($0)["refresh_token"] } == ["refresh-1", "refresh-2"])
    }

    @Test
    internal func rejectedRefreshIsAnInvalidGrant() async {
        let server = Server([(400, #"{"error":"invalid_grant","error_description":"session not found"}"#)])
        let token = MangaBakaToken(accessToken: "a", refreshToken: "r", expiresAt: nil, scope: nil)

        do {
            _ = try await oauth(server).refresh(token)
            Issue.record("Expected an error")
        } catch let error as MangaBakaOAuthError {
            #expect(error.isInvalidGrant)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        await #expect(throws: MangaBakaOAuthError.noRefreshToken) {
            try await oauth(Server([])).refresh(MangaBakaToken(accessToken: "a", refreshToken: nil, expiresAt: nil, scope: nil))
        }
    }

    @Test
    internal func revokeSendsTheRefreshToken() async throws {
        let server = Server([(200, "")])

        try await oauth(server).revoke(MangaBakaToken(accessToken: "a", refreshToken: "r", expiresAt: nil, scope: nil))

        let sent = try #require(server.requests.first)
        #expect(sent.url?.absoluteString == "https://mangabaka.org/auth/oauth2/revoke")
        #expect(form(sent) == ["client_id": "client-1", "token": "r", "token_type_hint": "refresh_token"])
    }

    @Test
    internal func tokensExpireWithLeewayAndNeverPrintTheirValues() {
        let token = MangaBakaToken(accessToken: "secret-access", refreshToken: "secret-refresh", expiresAt: Self.issued, scope: nil)
        var dumped = ""
        dump(token, to: &dumped)

        #expect(token.isExpired(at: Self.issued.addingTimeInterval(-30), leeway: 60))
        #expect(!token.isExpired(at: Self.issued.addingTimeInterval(-120), leeway: 60))
        #expect(!MangaBakaToken(accessToken: "a", refreshToken: nil, expiresAt: nil, scope: nil).isExpired())
        for text in ["\(token)", String(reflecting: token), dumped] {
            #expect(!text.contains("secret"), "\(text)")
        }
    }
}
