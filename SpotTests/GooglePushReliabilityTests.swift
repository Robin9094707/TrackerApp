import XCTest
@testable import SpotIntegration

final class GooglePushReliabilityTests: XCTestCase {
    func testRequestsWaitingForLoginSurviveReconnectAndSendOnlyOnce() {
        var subscriptions = GooglePushSubscriptions<String>()
        var sent: [String] = []
        let first = subscriptions.insert(whenReady: { sent.append("first") }, receive: { _ in false })
        _ = subscriptions.insert(whenReady: { sent.append("second") }, receive: { _ in false })
        // A failed socket has no login callbacks to consume. A replacement socket
        // consumes the same pending operations after receiving its LoginResponse.
        XCTAssertTrue(sent.isEmpty)
        subscriptions.takeReadyCallbacks().forEach { $0() }
        XCTAssertEqual(sent, ["first", "second"])
        subscriptions.takeReadyCallbacks().forEach { $0() }
        XCTAssertEqual(sent.count, 2, "A second login must not send the same Nova action twice.")
        XCTAssertNotNil(subscriptions.remove(first))
        XCTAssertFalse(subscriptions.isEmpty, "One tracker's response must not close another's stream.")
    }

    func testExpiredOrSignedOutRequestsCannotSendOnALaterLogin() {
        var subscriptions = GooglePushSubscriptions<String>()
        var sent = 0
        var failed = 0
        let expired = subscriptions.insert(whenReady: { sent += 1 }, receive: { message in
            if message == nil { failed += 1 }
            return false
        })
        _ = subscriptions.remove(expired)?.receive(nil)
        XCTAssertNil(subscriptions.remove(expired), "A stale timeout must be harmless.")
        subscriptions.takeReadyCallbacks().forEach { $0() }
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(failed, 1)
        _ = subscriptions.insert(whenReady: { sent += 1 }, receive: { _ in false })
        _ = subscriptions.removeAll()
        XCTAssertTrue(subscriptions.isEmpty)
        XCTAssertTrue(subscriptions.takeReadyCallbacks().isEmpty)
    }

    func testAdaptiveFallbackIsBoundedAndDoesNotChangeExplicitContributorModes() {
        var adaptive = GoogleLocationResponsePolicy()
        XCTAssertTrue(adaptive.needsAllAreasFallback(adaptive: true, tryingAgain: false, receivedUpdate: false))
        XCTAssertFalse(adaptive.needsAllAreasFallback(adaptive: true, tryingAgain: false, receivedUpdate: false))
        var fresh = GoogleLocationResponsePolicy()
        XCTAssertFalse(fresh.needsAllAreasFallback(adaptive: true, tryingAgain: false, receivedUpdate: true))
        XCTAssertFalse(fresh.needsAllAreasFallback(adaptive: false, tryingAgain: false, receivedUpdate: false))
        XCTAssertFalse(fresh.needsAllAreasFallback(adaptive: true, tryingAgain: true, receivedUpdate: false))
    }

    func testFragmentedAndCoalescedMCSReportsAreAllDeliveredInOrder() throws {
        var decoder = GoogleMCSDecoder()
        XCTAssertTrue(try decoder.append(Data([41])).isEmpty)
        XCTAssertTrue(try decoder.append(Data([3, 2, 11])).isEmpty)
        let frames = try decoder.append(Data([12, 8, 3, 21, 22, 23, 8, 1, 31]))
        XCTAssertEqual(frames.map(\.tag), [3, 8, 8])
        XCTAssertEqual(frames.map(\.payload), [Data([11, 12]), Data([21, 22, 23]), Data([31])])
    }
}
