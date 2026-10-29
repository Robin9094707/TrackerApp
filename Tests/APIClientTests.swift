import Foundation
import XCTest
@testable import RJTracker

final class APIStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private final class HeldAPIStubProtocol: URLProtocol {
    static var didStart: ((HeldAPIStubProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.didStart?(self) }
    override func stopLoading() { }

    func complete(status: Int, csrf: String, body: Data? = nil) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json", "X-CSRF-Token": csrf])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data("{\"status\":\"ok\",\"csrf_token\":\"\(csrf)\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class APIClientTests: XCTestCase {
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIStubProtocol.self]
        return APIClient(transport: URLSession(configuration: config), baseURL: URL(string: "https://example.test"))
    }
    func testRotatedCSRFInSecurityResponseIsUsedByNextMutation() async throws {
        let api = client()
        var calls = 0
        APIStubProtocol.handler = { request in
            calls += 1
            if calls == 2 { XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "rotated-test-token") }
            return (200, Data(#"{"status":"ok","csrf_token":"rotated-test-token"}"#.utf8))
        }
        _ = try await api.requestJSON(path: "/api/security/password", method: "POST", json: [:])
        _ = try await api.requestJSON(path: "/api/account/profile", method: "PATCH", json: [:])
        XCTAssertEqual(calls, 2)
    }
    func testRecentHistoryUsesCacheAndForceRefreshBypassesIt() async throws {
        let api = client()
        let tracker = PreviewFixtures.bootstrap.trackers[0]
        let payload = HistoryResponse(status: "ok", tracker: tracker, points: [])
        let bytes = try JSONEncoder().encode(payload)
        var calls = 0
        APIStubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/api/mobile/v1/history")
            return (200, bytes)
        }
        _ = try await api.history(tracker: tracker.ref, days: 1)
        _ = try await api.history(tracker: tracker.ref, days: 1)
        XCTAssertEqual(calls, 1)
        _ = try await api.history(tracker: tracker.ref, days: 1, force: true)
        XCTAssertEqual(calls, 2)
        api.clearHistoryCache()
        _ = try await api.history(tracker: tracker.ref, days: 1)
        XCTAssertEqual(calls, 3)
    }
    func testTargetedTrackerReadUsesReferenceQuery() async throws {
        let api = client()
        let tracker = PreviewFixtures.bootstrap.trackers[0]
        let trackerJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tracker))
        let bytes = try JSONSerialization.data(withJSONObject: ["tracker": trackerJSON])
        APIStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/mobile/v1/tracker")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, tracker.ref)
            return (200, bytes)
        }
        let result = try await api.tracker(reference: tracker.ref)
        XCTAssertEqual(result.ref, tracker.ref)
    }

    func testServerAddressKeepsProxyPathWithoutInheritedQueryOrFragment() async throws {
        let api = client()
        let oldURL = UserDefaults.standard.object(forKey: "serverURL")
        defer { UserDefaults.standard.set(oldURL, forKey: "serverURL"); APIStubProtocol.handler = nil }
        try api.configure(server: "https://example.test/tracker/?view=dashboard#account")
        APIStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/tracker/api/mobile/v1/session")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.url?.fragment)
            return (200, Data(#"{"status":"ok"}"#.utf8))
        }
        _ = try await api.session()
    }

    func testOldServerResponseCannotReplaceTokenOrExpireCurrentSession() async throws {
        let oldURL = UserDefaults.standard.object(forKey: "serverURL")
        defer { UserDefaults.standard.set(oldURL, forKey: "serverURL"); HeldAPIStubProtocol.didStart = nil }
        for status in [200, 401] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [HeldAPIStubProtocol.self]
            let api = APIClient(transport: URLSession(configuration: config), baseURL: URL(string: "https://old.example.test"))
            let token = api.csrfToken
            let started = expectation(description: "Old server request started: \(status)")
            var pending: HeldAPIStubProtocol?
            HeldAPIStubProtocol.didStart = { request in
                Task { @MainActor in pending = request; started.fulfill() }
            }
            let expired = expectation(description: "A stale response must not expire the new session")
            expired.isInverted = true
            let observer = NotificationCenter.default.addObserver(forName: .apiSessionExpired, object: nil, queue: .main) { _ in expired.fulfill() }
            defer { NotificationCenter.default.removeObserver(observer) }
            let read = Task { try await api.requestJSON(path: "/api/mobile/v1/session") }
            await fulfillment(of: [started], timeout: 2)
            try api.configure(server: "https://current.example.test")
            try XCTUnwrap(pending).complete(status: status, csrf: "stale-token")
            do {
                _ = try await read.value
                XCTFail("The old request must be invalidated")
            } catch is CancellationError { }
            catch { XCTFail("Expected cancellation, received \(error)") }
            XCTAssertEqual(api.csrfToken, token)
            await fulfillment(of: [expired], timeout: 0.05)
        }
    }

    func testCancelledHistoryWaiterDoesNotReceiveSharedResultOrCancelOtherReader() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeldAPIStubProtocol.self]
        let api = APIClient(transport: URLSession(configuration: config), baseURL: URL(string: "https://example.test"))
        let tracker = PreviewFixtures.bootstrap.trackers[0]
        let started = expectation(description: "Shared history request started")
        let joined = expectation(description: "Second reader joined")
        var pending: HeldAPIStubProtocol?
        HeldAPIStubProtocol.didStart = { request in
            Task { @MainActor in pending = request; started.fulfill() }
        }
        defer { HeldAPIStubProtocol.didStart = nil }
        let first = Task { try await api.history(tracker: tracker.ref, days: 1) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return try await api.history(tracker: tracker.ref, days: 1)
        }
        await fulfillment(of: [joined], timeout: 2)
        second.cancel()
        let bytes = try JSONEncoder().encode(HistoryResponse(status: "ok", tracker: tracker, points: []))
        try XCTUnwrap(pending).complete(status: 200, csrf: api.csrfToken, body: bytes)
        let result = try await first.value
        XCTAssertEqual(result.tracker.ref, tracker.ref)
        do {
            _ = try await second.value
            XCTFail("A cancelled history reader must not update its screen")
        } catch is CancellationError { }
        catch { XCTFail("Expected cancellation, received \(error)") }
    }
}
