import Foundation
import XCTest
@testable import RJTracker

@MainActor
final class TrackerRefreshTests: XCTestCase {
    private func checkCompletion(status: String, legacy: Bool = false) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIStubProtocol.self]
        let api = APIClient(transport: URLSession(configuration: config), baseURL: URL(string: "https://example.test"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(preferences: defaults, api: api)
        model.connectionState = .connected
        model.bootstrap = PreviewFixtures.bootstrap
        var tracker = try XCTUnwrap(model.trackers.first { $0.provider == "apple" })
        let original = tracker
        let oldTimestamp = tracker.reportTimestamp
        if legacy {
            tracker.location?.timestamp = oldTimestamp + 1
        } else {
            tracker.refresh = TrackerRefresh(completion: 11, status: status, available: true)
        }
        let trackerJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tracker))
        let bytes = try JSONSerialization.data(withJSONObject: ["tracker": trackerJSON])
        var gets = 0
        APIStubProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let response = legacy ? #"{"trackers":[{"ref":"apple:demo-keys"}]}"#
                    : #"{"trackers":[{"ref":"apple:demo-keys","refresh":{"completion":10,"status":"success","available":true}}]}"#
                return (200, Data(response.utf8))
            }
            gets += 1
            return (200, bytes)
        }
        defer { APIStubProtocol.handler = nil }
        await model.locate(original)
        XCTAssertTrue(model.isLocating(tracker))
        // A duplicate tap while pending must not start another request.
        await model.locate(original)
        for _ in 0..<40 where model.isLocating(tracker) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(model.isLocating(tracker))
        XCTAssertEqual(gets, 1)
        if !legacy { XCTAssertEqual(model.trackers.first { $0.ref == tracker.ref }?.reportTimestamp, oldTimestamp) }
        if status == "error" { XCTAssertTrue(model.statusMessage?.contains("fehlgeschlagen") == true) }
    }

    func testUnchangedReportReleasesButtonOnFirstCompletedResponse() async throws {
        try await checkCompletion(status: "success")
    }
    func testEmptyResponseReleasesButton() async throws {
        try await checkCompletion(status: "empty")
    }
    func testProviderErrorReleasesButtonAndShowsFailure() async throws {
        try await checkCompletion(status: "error")
    }
    func testOlderServerStillCompletesOnNewLocation() async throws {
        try await checkCompletion(status: "success", legacy: true)
    }
    func testExistingStartupCacheDecodesWithoutRefreshField() throws {
        let tracker = try JSONDecoder().decode(Tracker.self, from: Data(#"{"ref":"apple:old","name":"Old","provider":"apple"}"#.utf8))
        XCTAssertNil(tracker.refresh)
    }
}
