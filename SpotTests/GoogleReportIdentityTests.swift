import XCTest
@testable import SpotIntegration

final class GoogleReportIdentityTests: XCTestCase {
    private func report(altitude: Double = 0, name: String? = nil) -> LocationReportWrapper {
        var report = LocationReportWrapper(decryptedLocation: DecryptedLocation(latitude: 51.43, longitude: 6.76, altitude: altitude),
            time: Date(timeIntervalSince1970: 1000), accuracy: 10, status: .aggregated, isOwnReport: false)
        report.name = name
        return report
    }

    func testRepeatedReportsHaveStableIdentityAndAreCollapsed() {
        let first = report(), replay = report()
        XCTAssertNotEqual(first.id, replay.id)
        XCTAssertEqual(googleReportIdentity(first), googleReportIdentity(replay))
        XCTAssertEqual(uniqueGoogleReports([first, replay]).count, 1)
    }

    func testAltitudeAndSemanticLabelsPreserveDistinctReportsAndRowIDs() {
        let reports = [report(), report(altitude: 30), report(name: "Ort A"), report(name: "Ort B")]
        XCTAssertEqual(uniqueGoogleReports(reports + reports).count, 4)
        XCTAssertEqual(Set(reports.map(googleReportIdentity)).count, 4)
    }

    func testEncryptedPayloadsAndSemanticOnlyReportsRemainDistinct() {
        var first = LocationReportWrapper(encryptedLocation: .init(), time: Date(timeIntervalSince1970: 1000),
            accuracy: 10, status: .aggregated, isOwnReport: false)
        var second = first
        first.encryptedLocation?.lastAggregatedAccuracy = 10
        second.encryptedLocation?.lastAggregatedAccuracy = 20
        let a = LocationReportWrapper(time: first.time, name: "A|B")
        let b = LocationReportWrapper(time: first.time, name: "A")
        XCTAssertEqual(uniqueGoogleReports([first, second, a, b, a]).count, 4)
        XCTAssertEqual(Set([first, second, a, b].map(googleReportIdentity)).count, 4)
    }
}
