import XCTest
@testable import SpotIntegration

final class GoogleCollectionTests: XCTestCase {
    func testExistingTrackersKeepCollectionAndPauseIsAccountAndDeviceSpecific() {
        let suite = "GoogleCollectionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(GoogleCollectionPreferences.enabled(account: "one@example.invalid", deviceID: "tag", defaults: defaults))
        GoogleCollectionPreferences.set(false, account: "one@example.invalid", deviceID: "tag", defaults: defaults)
        XCTAssertFalse(GoogleCollectionPreferences.enabled(account: "ONE@example.invalid", deviceID: "tag", defaults: defaults))
        XCTAssertTrue(GoogleCollectionPreferences.enabled(account: "two@example.invalid", deviceID: "tag", defaults: defaults))
        XCTAssertTrue(GoogleCollectionPreferences.enabled(account: "one@example.invalid", deviceID: "tag-2", defaults: defaults))
        GoogleCollectionPreferences.set(true, account: "one@example.invalid", deviceID: "tag", defaults: defaults)
        XCTAssertTrue(GoogleCollectionPreferences.enabled(account: "one@example.invalid", deviceID: "tag", defaults: defaults))
    }
}
