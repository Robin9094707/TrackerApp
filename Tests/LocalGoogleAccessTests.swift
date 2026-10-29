import XCTest
import Foundation
@testable import RJTracker

@MainActor final class LocalGoogleAccessTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "LocalGoogleTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIStubProtocol.self]
        let previous = UserDefaults.standard.object(forKey: "serverURL")
        addTeardownBlock { UserDefaults.standard.set(previous, forKey: "serverURL") }
        return APIClient(transport: URLSession(configuration: config), baseURL: URL(string: "https://offline.example.invalid"))
    }
    func testUpgradeFromServerModeKeepsLocalGoogleAccessibleAcrossEveryServerState() {
        let preferences = defaults()
        preferences.set(false, forKey: "native.localMode")
        let model = AppModel(preferences: preferences)
        let states: [AppModel.ConnectionState] = [.restoring, .disconnected, .connecting, .needsTwoFactor, .connected]
        for state in states {
            model.connectionState = state
            XCTAssertTrue(model.showsMainInterface(localGoogleCredentials: true))
            XCTAssertEqual(model.showsMainInterface(localGoogleCredentials: false), state == .connected)
        }
        XCTAssertEqual(preferences.object(forKey: "native.localMode") as? Bool, false)
        model.localGoogleFallbackEnabled = false
        model.connectionState = .disconnected
        XCTAssertFalse(model.showsMainInterface(localGoogleCredentials: true))
        XCTAssertFalse(AppModel(preferences: preferences).localGoogleFallbackEnabled)
    }
    func testGoogleControlsAreScopedToAllAndGoogleAndEmptyAppleFilterStaysEmpty() {
        let model = AppModel(preferences: defaults())
        model.localGoogleTrackers = [Tracker(ref: "google:local", name: "Lokal", provider: "google")]
        for provider in ["all", "google", "apple", "samsung", "fusion"] {
            model.providerFilter = provider
            XCTAssertEqual(model.showsGoogleControls, ["all", "google"].contains(provider))
            XCTAssertEqual(model.filteredTrackers.count, model.showsGoogleControls ? 1 : 0)
        }
        model.selectedGroup = "server-group"; model.selectedScope = .favorites; model.searchText = "no match"
        model.useLocalGoogle()
        XCTAssertEqual(model.providerFilter, "google")
        XCTAssertNil(model.selectedGroup)
        XCTAssertEqual(model.filteredTrackers.count, 1)
    }
    func testUnreachableServerDoesNotBlockLocalAccessAndCanReconnect() async throws {
        let model = AppModel(preferences: defaults(), api: client())
        model.serverURL = "https://offline.example.invalid"
        var available = false
        APIStubProtocol.handler = { request in
            if !available { throw URLError(.notConnectedToInternet) }
            if request.url?.path.hasSuffix("/session") == true { return (200, Data(#"{"status":"ok","authenticated":true}"#.utf8)) }
            return (200, try JSONEncoder().encode(PreviewFixtures.bootstrap))
        }
        await model.start()
        XCTAssertEqual(model.connectionState, .disconnected)
        XCTAssertTrue(model.showsMainInterface(localGoogleCredentials: true))
        XCTAssertNotNil(model.refreshError)
        available = true
        await model.retryServerConnection()
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertTrue(model.serverActionsAvailable)
    }
    func testSavedServerInterfaceIsAvailableBeforeNetworkRestoration() {
        let model = AppModel(preferences: defaults(), api: client())
        model.serverURL = "https://saved.example.invalid"; model.username = "saved-user"
        model.connectionState = .restoring
        XCTAssertTrue(model.showsMainInterface(localGoogleCredentials: false))
        XCTAssertFalse(model.serverActionsAvailable)
        model.serverReconnectEnabled = false
        XCTAssertFalse(model.showsMainInterface(localGoogleCredentials: false))
    }

    func testMalformedLocalReportPreservesValidServerLocationAndMetadata() throws {
        let model = AppModel(preferences: defaults())
        let location = TrackerLocation(latitude: 52.5, longitude: 13.3, accuracyM: 25, timestamp: 100)
        let server = Tracker(ref: "google:shared-tag", name: "Mein Koffer", provider: "google",
                             location: location, favorite: true, groups: ["travel"])
        var bootstrap = PreviewFixtures.bootstrap
        bootstrap.trackers = [server]
        model.bootstrap = bootstrap
        model.localGoogleTrackers = [Tracker(ref: server.ref, name: "Lokal", provider: "google",
            location: TrackerLocation(latitude: 999, longitude: 13.3, timestamp: 200))]
        let merged = try XCTUnwrap(model.trackers.first)
        XCTAssertEqual(merged.location, location)
        XCTAssertEqual(merged.name, server.name)
        XCTAssertEqual(merged.favorite, true)
        XCTAssertEqual(merged.groups, ["travel"])
        XCTAssertEqual(model.trackers.count, 1)
    }

    func testValidLocalReportRecoversInvalidServerLocationAndKeepsNewestUsableReport() throws {
        let model = AppModel(preferences: defaults())
        let localLocation = TrackerLocation(latitude: 52.5, longitude: 13.3, accuracyM: 10, timestamp: 100)
        var server = Tracker(ref: "google:shared-tag", name: "Mein Koffer", provider: "google",
            location: TrackerLocation(latitude: 999, longitude: 13.3, timestamp: 200))
        var bootstrap = PreviewFixtures.bootstrap
        bootstrap.trackers = [server]
        model.bootstrap = bootstrap
        model.localGoogleTrackers = [Tracker(ref: server.ref, name: "Lokal", provider: "google",
                                             location: localLocation, status: "In der Nähe")]
        XCTAssertEqual(model.trackers.first?.validLocation, localLocation)
        XCTAssertEqual(model.trackers.first?.status, "In der Nähe")
        server.location = TrackerLocation(latitude: 53, longitude: 14, timestamp: 300)
        bootstrap.trackers = [server]
        model.bootstrap = bootstrap
        XCTAssertEqual(model.trackers.first?.validLocation, server.location)
        XCTAssertEqual(model.trackers.first?.reportTimestamp, 300)
    }

}
