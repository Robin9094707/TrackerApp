import Foundation
import XCTest
@testable import RJTracker

private final class SessionRaceStubProtocol: URLProtocol {
    static var didStart: ((SessionRaceStubProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.didStart?(self) }
    override func stopLoading() { }

    func complete(_ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class AppSessionTests: XCTestCase {
    func testHeldLogoutCannotDiscardNewLoginOrResetItsFilters() async throws {
        let originalURL = UserDefaults.standard.object(forKey: "serverURL")
        let originalUsername = UserDefaults.standard.object(forKey: "username")
        let suite = "AppSessionTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            SessionRaceStubProtocol.didStart = nil
            UserDefaults.standard.set(originalURL, forKey: "serverURL")
            UserDefaults.standard.set(originalUsername, forKey: "username")
            preferences.removePersistentDomain(forName: suite)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionRaceStubProtocol.self]
        let api = APIClient(transport: URLSession(configuration: configuration), baseURL: URL(string: "https://session.example.test"))
        let model = AppModel(preferences: preferences, api: api)
        model.serverURL = "https://session.example.test"
        model.username = "new-user"
        model.connectionState = .connected
        model.bootstrap = PreviewFixtures.bootstrap
        let logoutStarted = expectation(description: "Logout is waiting for the old server")
        var pendingLogout: SessionRaceStubProtocol?
        SessionRaceStubProtocol.didStart = { request in
            Task { @MainActor in
                if request.request.url?.path == "/api/logout" {
                    pendingLogout = request
                    logoutStarted.fulfill()
                } else {
                    request.complete(#"{"status":"two_factor_required"}"#)
                }
            }
        }
        let logout = Task { await model.signOut() }
        await fulfillment(of: [logoutStarted], timeout: 2)
        await model.connect(password: "test-password")
        XCTAssertEqual(model.connectionState, .needsTwoFactor)
        model.providerFilter = "google"
        try XCTUnwrap(pendingLogout).complete(#"{"status":"ok"}"#)
        await logout.value
        XCTAssertEqual(model.connectionState, .needsTwoFactor)
        XCTAssertTrue(model.serverReconnectEnabled)
        XCTAssertEqual(model.providerFilter, "google")
    }
}
