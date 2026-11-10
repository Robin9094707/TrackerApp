import XCTest
@testable import RJTracker

final class DashboardInsightsTests: XCTestCase {
    private let now = 1_800_000_000

    private func tracker(_ name: String, age: Int?, battery: String? = nil) -> Tracker {
        Tracker(ref: "apple:" + name, name: name, provider: "apple",
                lastSeenTs: age.map { now - $0 }, battery: battery)
    }

    func testBatteryParsingAndLowDetection() {
        XCTAssertEqual(DashboardInsights.batteryPercent("77 %"), 77)
        XCTAssertEqual(DashboardInsights.batteryPercent("12%"), 12)
        XCTAssertNil(DashboardInsights.batteryPercent("Mehrere Quellen"))
        XCTAssertTrue(DashboardInsights.batteryIsLow("15 %"))
        XCTAssertTrue(DashboardInsights.batteryIsLow("Niedrig"))
        XCTAssertFalse(DashboardInsights.batteryIsLow("80 %"))
        XCTAssertFalse(DashboardInsights.batteryIsLow(nil))
    }

    func testInsightsOrderBatteryThenOldestStaleThenMissingAndRespectLimit() {
        let trackers = [tracker("Frisch", age: 60), tracker("Alt", age: 13 * 3600),
                        tracker("Uralt", age: 5 * 86400), tracker("Leer", age: nil),
                        tracker("Schwach", age: 120, battery: "10 %")]
        let rows = DashboardInsights.insights(for: trackers, now: now)
        XCTAssertEqual(rows.map(\.title), ["Schwach", "Uralt", "Alt", "Leer"])
        XCTAssertEqual(rows.map(\.kind), [.battery, .stale, .stale, .noLocation])
        XCTAssertEqual(rows[1].detail, "Keine neue Meldung seit 5 Tagen")
        XCTAssertEqual(DashboardInsights.insights(for: trackers, now: now, limit: 2).count, 2)
        XCTAssertEqual(DashboardInsights.freshCount(trackers, now: now), 2)
        XCTAssertTrue(DashboardInsights.insights(for: [tracker("Frisch", age: 60)], now: now).isEmpty)
    }

    func testGreetingFollowsTimeOfDay() {
        XCTAssertEqual(DashboardInsights.greeting(hour: 7), "Guten Morgen")
        XCTAssertEqual(DashboardInsights.greeting(hour: 14), "Guten Tag")
        XCTAssertEqual(DashboardInsights.greeting(hour: 20), "Guten Abend")
        XCTAssertEqual(DashboardInsights.greeting(hour: 2), "Gute Nacht")
    }
}
