import XCTest
@testable import RJTracker

final class TrackerStartupCacheTests: XCTestCase {
    func testCachedCatalogSurvivesRelaunchAndIsIsolatedByIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = TrackerStartupCache(directory: folder)
        let tracker = Tracker(ref: "apple:retained", name: "Schlüssel", provider: "apple")
        let date = Date(timeIntervalSince1970: 1_000)
        await cache.save([tracker], date: date, identity: "https://one.invalid|robin")
        let relaunched = TrackerStartupCache(directory: folder)
        let restored = await relaunched.load(identity: "https://one.invalid|robin")
        XCTAssertEqual(restored?.trackers, [tracker])
        XCTAssertEqual(restored?.date, date)
        let otherAccount = await relaunched.load(identity: "https://one.invalid|other")
        let otherServer = await relaunched.load(identity: "https://two.invalid|robin")
        XCTAssertNil(otherAccount); XCTAssertNil(otherServer)
        await relaunched.clear(identity: "https://one.invalid|robin")
        let cleared = await cache.load(identity: "https://one.invalid|robin")
        XCTAssertNil(cleared)
    }
}
