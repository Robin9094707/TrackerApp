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
        sample.latitude = -32
        sample.address = AddressInfo(label: "=HYPERLINK(\"example\")")
        let csv = HistoryAnalysis.csv([sample])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"example\"\")\""))
        XCTAssertTrue(csv.contains("1970-01-01T00:16:40Z"))
        XCTAssertTrue(csv.contains("\"-32.0\""))
        XCTAssertFalse(csv.contains("'-32"))
    }

    func testGPXSeparatesDiscontinuousTracks() {
        let gpx = HistoryAnalysis.gpx([point(1000), point(5000)])
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertTrue(gpx.contains("http://www.topografix.com/GPX/1/1"))
    }

    @MainActor
    func testGuestPasswordFormEncodingPreservesSpecialCharacters() throws {
        let password = "a+b &?=ä#123"
        let data = APIClient.formBody(["pw": password])
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertEqual(URLComponents(string: "https://example.test/?" + encoded)?.queryItems?.first?.value, password)
        XCTAssertEqual(NativeShareOptions().form["show_history"], "0")
    }

    func testPollingBoundsAndOrderingMatchServer() {
        XCTAssertTrue(PollingInterval(minimum: 15, maximum: 300).isValid(for: "apple"))
        XCTAssertFalse(PollingInterval(minimum: 14, maximum: 300).isValid(for: "apple"))
        XCTAssertFalse(PollingInterval(minimum: 60, maximum: 30).isValid(for: "google"))
        XCTAssertFalse(PollingInterval(minimum: 20, maximum: 601).isValid(for: "samsung"))
    }

    func testOverviewMovesObjectsAbovePanelAndUnwrapsDateLine() throws {
        let locations = [TrackerLocation(latitude: 52, longitude: 179.9), TrackerLocation(latitude: 52.01, longitude: -179.9)]
        let region = try XCTUnwrap(RJMapCamera.overview(locations: locations, panelCoverage: 0.48))
        XCTAssertLessThan(region.center.latitude, 52)
        XCTAssertLessThan(region.span.longitudeDelta, 1)
        XCTAssertNil(RJMapCamera.overview(locations: [], panelCoverage: 0.5))
    }

    @MainActor
    func testFilterPreferencesSurviveNewAppModel() throws {
        let suite = "TrackerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppModel(preferences: defaults)
        first.selectedSort = .newest
        first.selectedScope = .favorites
        first.providerFilter = "fusion"
        first.selectedGroup = "travel"
        let restored = AppModel(preferences: defaults)
        XCTAssertEqual(restored.selectedSort, .newest)
        XCTAssertEqual(restored.selectedScope, .favorites)
        XCTAssertEqual(restored.providerFilter, "fusion")
        XCTAssertEqual(restored.selectedGroup, "travel")
        restored.selectedSort = .nearest
        XCTAssertEqual(AppModel(preferences: defaults).selectedSort, .nearest)
        defaults.set("removed-value", forKey: "tracker.sort")
        XCTAssertEqual(AppModel(preferences: defaults).selectedSort, .favorites)
    }

    func testMixedNetworksNeverBecomeOneTravelLine() {
        let points = [point(1000, network: "apple"), point(1020, network: "google"), point(1060, network: "apple"), point(1080, network: "google")]
        let segments = HistoryAnalysis.sourceSegments(points)
        XCTAssertEqual(segments.map { $0.points.count }, [2, 2])
        XCTAssertTrue(segments.allSatisfy { Set($0.points.map { $0.network }).count == 1 })
        XCTAssertEqual(HistoryAnalysis.gpx(points).components(separatedBy: "<trkseg>").count - 1, 2)
    }

    func testHistorySimplificationPreservesCornersEndpointsAndOriginalReports() {
        let original = (0..<500).map { i in
            HistoryPoint(latitude: 52 + Double(min(i, 250)) * 0.00001,
                         longitude: 13 + Double(max(0, i - 250)) * 0.00001,
                         timestamp: 1000 + i * 2, network: "apple")
        }
        let prepared = HistoryAnalysis.prepare(original, networks: ["apple"])
        XCTAssertEqual(prepared.points.count, 500)
        XCTAssertLessThan(prepared.mapSegments.first?.points.count ?? 500, 20)
        XCTAssertEqual(prepared.mapSegments.first?.points.first?.id, original.first?.id)
        XCTAssertEqual(prepared.mapSegments.first?.points.last?.id, original.last?.id)
        XCTAssertTrue(prepared.mapSegments.first?.points.contains(where: { $0.id == original[250].id }) == true)
        XCTAssertEqual(prepared.mapPoints.count, 80)
        XCTAssertEqual(prepared.indexByID[original[250].id], 250)
        XCTAssertEqual(HistoryAnalysis.csv(prepared.points).components(separatedBy: "\r\n").count, 501)
    }

    func testHistoryTimeScrubbingHandlesIrregularGapsAndBounds() {
        let samples = [point(1000), point(1010), point(8000)]
        XCTAssertEqual(HistoryAnalysis.nearestIndex(to: 990, in: samples), 0)
        XCTAssertEqual(HistoryAnalysis.nearestIndex(to: 1007, in: samples), 1)
        XCTAssertEqual(HistoryAnalysis.nearestIndex(to: 7000, in: samples), 2)
        XCTAssertEqual(HistoryAnalysis.nearestIndex(to: 9000, in: samples), 2)
        XCTAssertEqual(HistoryAnalysis.nearestIndex(to: 1000, in: []), 0)
    }

    func testTimelineGroupsUseLocalCalendarAndKeepNetworkGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        let samples = [point(3600), point(86400), point(90000, network: "google")]
        let prepared = HistoryAnalysis.prepare(samples, networks: ["apple", "google"], calendar: calendar)
        XCTAssertEqual(prepared.days.map { $0.points.count }, [2, 1])
        XCTAssertEqual(prepared.days.first?.points.first?.timestamp, 90000)
        XCTAssertTrue(prepared.mapSegments.allSatisfy { $0.points.count == 1 })
    }

    private func point(_ timestamp: Int, network: String = "apple") -> HistoryPoint {
        HistoryPoint(latitude: 52.5163, longitude: 13.3777, accuracyM: 20, timestamp: timestamp, network: network)
    }
}

