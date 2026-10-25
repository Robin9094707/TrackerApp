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

}
