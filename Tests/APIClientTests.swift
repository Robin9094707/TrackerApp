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
}
