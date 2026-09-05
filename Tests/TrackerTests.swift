import XCTest
import CoreLocation
@testable import RJTracker

final class TrackerTests: XCTestCase {
    func testMobileBootstrapContractAndFusionSources() throws {
        let data = PreviewFixtures.bootstrap
        XCTAssertEqual(data.trackers.count, 4)
        XCTAssertEqual(data.trackers[0].apiID, "demo-bag")
        XCTAssertEqual(data.trackers[0].fusionNetworkNames, ["apple", "google", "samsung"])
        XCTAssertEqual(data.trackers[0].latestSourceName, "apple")
        XCTAssertEqual(data.trackers[0].sourceHealth?.objectValue?["google"]?.objectValue?["accuracy_m"]?.numberValue, 45)
    }

    func testFiltersMatchNotesAndExcludeHiddenTrackers() {
        var trackers = PreviewFixtures.bootstrap.trackers
        trackers[0].hidden = true
        XCTAssertTrue(TrackerQuery(text: "Innenfach").apply(to: trackers).isEmpty)
        trackers[0].hidden = false
        XCTAssertEqual(TrackerQuery(text: "innenfach").apply(to: trackers).map(\.ref), ["fusion:demo-bag"])
        XCTAssertEqual(TrackerQuery(provider: "apple", scope: .favorites).apply(to: trackers).count, 1)
    }

    func testFreshnessAndNearestSortingHandleMissingLocations() {
        let trackers = PreviewFixtures.bootstrap.trackers
        XCTAssertEqual(TrackerQuery(scope: .missing).apply(to: trackers).count, 2)
        let sorted = TrackerQuery(sort: .nearest).apply(to: trackers, origin: CLLocation(latitude: 52.5163, longitude: 13.3777))
        XCTAssertEqual(sorted.first?.name, "Rucksack")
        XCTAssertEqual(sorted.last?.name, "Koffer")
    }

    func testStableProviderIDsPreserveColonsAndSlashes() {
        let tracker = Tracker(ref: "google:a:b/c", name: "Test", provider: "google")
        XCTAssertEqual(tracker.apiID, "a:b/c")
    }

    func testHistoryDeduplicationPreservesSeparateNetworks() {
        let apple = point(1000, network: "apple")
        let google = point(1000, network: "google")
        let filtered = HistoryAnalysis.filtered([apple, apple, google], networks: ["apple", "google"])
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(HistoryAnalysis.filtered(filtered, networks: ["apple"]).count, 1)
    }

    func testHistoryDoesNotDrawAcrossGapsOrImpossibleJumps() {
        let points = [point(1000), point(1060), point(5000), HistoryPoint(latitude: 0, longitude: 0, timestamp: 5001)]
        XCTAssertEqual(HistoryAnalysis.segments(points).map { $0.points.count }, [2, 1, 1])
    }

    func testInvalidCoordinatesAndZeroTimeAreExcluded() {
        let invalid = HistoryPoint(latitude: 200, longitude: 13, timestamp: 100)
        XCTAssertTrue(HistoryAnalysis.filtered([invalid, point(0)], networks: ["apple", "unknown"]).isEmpty)
    }

    func testCSVQuotesAddressAndNeutralizesSpreadsheetFormula() {
        var sample = point(1000)
        sample.address = AddressInfo(label: "=HYPERLINK(\"example\")")
        let csv = HistoryAnalysis.csv([sample])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"example\"\")\""))
        XCTAssertTrue(csv.contains("1970-01-01T00:16:40Z"))
    }

    func testGPXSeparatesDiscontinuousTracks() {
        let gpx = HistoryAnalysis.gpx([point(1000), point(5000)])
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertTrue(gpx.contains("http://www.topografix.com/GPX/1/1"))
    }

    private func point(_ timestamp: Int, network: String = "apple") -> HistoryPoint {
        HistoryPoint(latitude: 52.5163, longitude: 13.3777, accuracyM: 20, timestamp: timestamp, network: network)
    }
}
