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

    func testDiskRoundTripPreservesAccuracyAltitudeLabelsAndReplayDeduplication() {
        let manager = TokenManager.sharedInstance
        let previous = manager.username
        manager.username = "reports-\(UUID().uuidString)@example.invalid"
        defer { manager.username = previous }
        var precise = report()
        precise.accuracy = 5
        let reports = [report(), precise, report(altitude: 30), report(name: "Beschrifteter Standort"),
            LocationReportWrapper(time: Date(timeIntervalSince1970: 1000), name: "Zuhause")]
        let expected = Set(reports.map(googleReportIdentity))
        // Separate batches reproduce late reports that only differ in accuracy.
        for report in reports {
            let refresh = RefreshWrapper(time: report.time, contributorType: .AtAllAreas, reports: [report])
            storeReportsOnDisk(requestDate: report.time, contributorType: .AtAllAreas,
                canonicDeviceId: "round-trip", decryptedRefresh: refresh)
            storeReportsOnDisk(requestDate: report.time, contributorType: .AtAllAreas,
                canonicDeviceId: "round-trip", decryptedRefresh: refresh)
        }
        let restored = loadReportsFromDisk(for: "round-trip").flatMap(\.reports)
        XCTAssertEqual(restored.count, reports.count)
        XCTAssertEqual(Set(restored.map(googleReportIdentity)), expected)
    }

    @MainActor
    func testBackgroundHistoryCompactionKeepsReportsArrivingDuringWork() async throws {
        var metadata = DeviceMetadata()
        metadata.trackerInformation.deviceRegistration.canonicID.id = "compaction-" + UUID().uuidString
        metadata.trackerInformation.deviceRegistration.deviceDescription.userDefinedName = "Test-Tracker"
        let device = try XCTUnwrap(convertToLocalFindMyDevice(deviceMetadata: metadata, existingDevices: []))
        let initial = (0..<200).map { report(altitude: Double($0)) }
        device.appendHistory(RefreshWrapper(time: .now, contributorType: .AtAllAreas, reports: initial))
        await Task.yield()
        let late = report(altitude: 999)
        device.appendHistory(RefreshWrapper(time: .now, contributorType: .AtAllAreas, reports: [late, initial[0]]))
        await device.historyCompaction?.value
        let result = device.refreshes.flatMap(\.reports)
        XCTAssertEqual(result.count, 201)
        XCTAssertEqual(Set(result.map(googleReportIdentity)), Set((initial + [late]).map(googleReportIdentity)))
    }

}
