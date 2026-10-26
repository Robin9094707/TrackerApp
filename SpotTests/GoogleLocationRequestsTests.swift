import XCTest
@testable import SpotIntegration

final class GoogleLocationRequestsTests: XCTestCase {
    func testResponsesFinishIndividuallyAndOldTimeoutCannotFinishRetry() throws {
        var requests = GoogleLocationRequests()
        let bag = try XCTUnwrap(requests.begin("bag"))
        let keys = try XCTUnwrap(requests.begin("keys"))
        XCTAssertNil(requests.begin("bag"))
        XCTAssertTrue(requests.finish("bag", token: bag))
        XCTAssertEqual(requests.pending, ["keys"])
        let retry = try XCTUnwrap(requests.begin("bag"))
        XCTAssertFalse(requests.finish("bag", token: bag)) // old stream packet or deadline
        XCTAssertEqual(requests.pending, ["bag", "keys"])
        XCTAssertTrue(requests.finish("keys", token: keys))
        XCTAssertTrue(requests.finish("bag", token: retry))
        XCTAssertTrue(requests.pending.isEmpty)
        let previousAccount = try XCTUnwrap(requests.begin("bag"))
        requests.reset()
        _ = requests.begin("bag")
        XCTAssertFalse(requests.finish("bag", token: previousAccount))
    }
}
