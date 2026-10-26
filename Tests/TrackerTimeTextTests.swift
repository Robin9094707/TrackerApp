import XCTest
@testable import RJTracker

final class TrackerTimeTextTests: XCTestCase {
    func testGermanMinuteAndHourBoundariesAcrossProviders() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (seconds, text) in [(0.0, "Gerade eben"), (59, "Gerade eben"), (60, "vor einer Minute"),
                                (120, "vor 2 Minuten"), (3599, "vor 59 Minuten"),
                                (3600, "vor einer Stunde"), (7200, "vor 2 Stunden")] {
            XCTAssertEqual(TrackerTimeText.age(of: now.addingTimeInterval(-seconds), now: now), text)
        }
        XCTAssertEqual(TrackerTimeText.age(of: now.addingTimeInterval(30), now: now), "Gerade eben")
    }
}
