import XCTest
@testable import SpotIntegration

final class GoogleCookieTests: XCTestCase {
    func testCookieRestorationFromGenericExecutorUsesMainThread() async throws {
        // Reproduces the v5.1 launch crash: googleCallback runs off the main actor.
        let onMain = try await Task.detached {
            try await googleCallback(seconds: 10) { done in
                CookieCache.getAllCookies { _ in done(.success(Thread.isMainThread)) }
            }
        }.value
        XCTAssertTrue(onMain)
        let insertionOnMain = try await Task.detached {
            try await googleCallback(seconds: 10) { done in
                CookieCache.addCookies(cookies: []) { done(.success(Thread.isMainThread)) }
            }
        }.value
        XCTAssertTrue(insertionOnMain)
    }
}
