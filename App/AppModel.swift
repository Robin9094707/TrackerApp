import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable { case restoring, disconnected, connecting, needsTwoFactor, connected }

    var connectionState: ConnectionState = .restoring
    var bootstrap: BootstrapResponse?
    var isRefreshing = false
    var locatingRefs: Set<String> = []
    var notificationRefs: Set<String> = []
    var errorMessage: String?
    var lastRefresh: Date?
    var refreshError: String?
    var statusMessage: String?
    var selectedScope: TrackerScope = .all
    var selectedSort: TrackerSort = .favorites
    var selectedGroup: String?
    var updatingRefs: Set<String> = []
    var isLocatingAll = false
    let locationService = LocationService()
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var username: String = UserDefaults.standard.string(forKey: "username") ?? ""
    var providerFilter = "all"
    var searchText = ""

    var trackers: [Tracker] { bootstrap?.trackers ?? [] }
    var filteredTrackers: [Tracker] {
        TrackerQuery(text: searchText, provider: providerFilter, scope: selectedScope,
                     sort: selectedSort, group: selectedGroup)
            .apply(to: trackers, origin: locationService.location)
    }


    init() {
        NotificationCenter.default.addObserver(forName: .apiSessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.connectionState = .disconnected }
        }
        NotificationCenter.default.addObserver(forName: .apnsTokenAvailable, object: nil, queue: .main) { _ in
            Task { @MainActor in await PushManager.shared.registerIfPossible() }
        }
    }

    func start() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            bootstrap = PreviewFixtures.bootstrap
            connectionState = .connected
            lastRefresh = Date()
            return
        }
        #endif
        guard !serverURL.isEmpty else { connectionState = .disconnected; return }
        do {
            try APIClient.shared.configure(server: serverURL)
            let session = try await APIClient.shared.session()
            if session.authenticated == true {
                connectionState = .connected
                await refresh()
                await PushManager.shared.registerIfPossible()
            } else { connectionState = .disconnected }
        } catch {
            DebugLogger.shared.log("Restore failed: \(error.localizedDescription)")
            connectionState = .disconnected
        }
    }

    func connect(password: String) async {
        errorMessage = nil
        connectionState = .connecting
        do {
            let result = try await APIClient.shared.pair(server: serverURL, username: username, password: password)
            if result.status == "two_factor_required" { connectionState = .needsTwoFactor; return }
            guard result.status == "ok" else { throw APIError.message(result.message ?? "Anmeldung fehlgeschlagen.") }
            connectionState = .connected
            await refresh()
            await PushManager.shared.registerIfPossible()
            Haptics.success()
        } catch {
            connectionState = .disconnected
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    func verify2FA(code: String) async {
        do {
            let result = try await APIClient.shared.pair2FA(code: code)
            guard result.status == "ok" else { throw APIError.message(result.message ?? "Code ungültig.") }
            connectionState = .connected
            await refresh()
            await PushManager.shared.registerIfPossible()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        guard connectionState == .connected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let previousTimestamp = UserDefaults.standard.integer(forKey: "lastAlertTimestamp")
            let data = try await APIClient.shared.bootstrap()
            guard connectionState == .connected else { return }
            bootstrap = data
            lastRefresh = Date()
            refreshError = nil
            let events = data.alerts?.events ?? []
            if data.push?.serverConfigured != true {
                for event in events.filter({ ($0.ts ?? 0) > previousTimestamp }).reversed() {
                    await PushManager.shared.scheduleLocal(event: event)
                }
            }
            let newest = events.compactMap(\.ts).max() ?? previousTimestamp
            UserDefaults.standard.set(newest, forKey: "lastAlertTimestamp")
            DebugLogger.shared.log("Bootstrap loaded: \(data.trackers.count) trackers")
        } catch is CancellationError {
            return
        } catch {
            refreshError = error.localizedDescription
            DebugLogger.shared.log("Refresh failed: \(error.localizedDescription)")
        }
    }

    func isLocating(_ tracker: Tracker) -> Bool { locatingRefs.contains(tracker.ref) }
    func isUpdatingNotification(_ tracker: Tracker) -> Bool { notificationRefs.contains(tracker.ref) }

    func locate(_ tracker: Tracker) async {
        guard !locatingRefs.contains(tracker.ref), !isLocatingAll else { return }
        locatingRefs.insert(tracker.ref)
        statusMessage = nil
        let oldTimestamp = tracker.reportTimestamp
        defer { locatingRefs.remove(tracker.ref) }
        do {
            Haptics.impact()
            _ = try await APIClient.shared.action("locate", payload: ["tracker": tracker.ref])
            for _ in 0..<9 {
                try await Task.sleep(for: .seconds(5))
                guard connectionState == .connected else { return }
                await refresh()
                if let updated = trackers.first(where: { $0.ref == tracker.ref }), updated.reportTimestamp > oldTimestamp {
                    statusMessage = "Neuer Standort für \(tracker.name) empfangen."
                    Haptics.success()
                    return
                }
            }
            statusMessage = "Ortung angefordert. Für \(tracker.name) liegt noch keine neuere Meldung vor."
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription; Haptics.warning() }
    }

    func locateAll() async {
        guard !isLocatingAll, locatingRefs.isEmpty else { return }
        isLocatingAll = true
        statusMessage = nil
        defer { isLocatingAll = false }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["all": true])
            statusMessage = "Ortung für alle Objekte angefordert. Neue Meldungen erscheinen automatisch."
            Haptics.impact()
            try await Task.sleep(for: .seconds(15))
            await refresh()
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription; Haptics.warning() }
    }

    func setFavorite(_ tracker: Tracker) async {
        guard !updatingRefs.contains(tracker.ref) else { return }
        updatingRefs.insert(tracker.ref)
        defer { updatingRefs.remove(tracker.ref) }
        let newValue = tracker.favorite != true
        do {
            _ = try await APIClient.shared.requestJSON(
                path: "/api/v2/trackers/\(tracker.provider)/\(tracker.apiID)/preferences",
                method: "POST", json: ["favorite": newValue])
            if let index = bootstrap?.trackers.firstIndex(where: { $0.ref == tracker.ref }) {
                bootstrap?.trackers[index].favorite = newValue
            }
            await refresh()
            Haptics.success()
        } catch { errorMessage = error.localizedDescription }
    }

    func runAction(_ action: String, payload: [String: Any]) async throws {
        _ = try await APIClient.shared.action(action, payload: payload)
        await refresh()
        Haptics.success()
    }

    func foregroundUpdates() async {
        while !Task.isCancelled {
            guard connectionState == .connected else { return }
            await refresh()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }

    func setFoundNotification(_ tracker: Tracker, enabled: Bool) async {
        guard !notificationRefs.contains(tracker.ref) else { return }
        notificationRefs.insert(tracker.ref)
        defer { notificationRefs.remove(tracker.ref) }
        do {
            _ = try await APIClient.shared.action("set_found_notification", payload: [
                "tracker": tracker.ref,
                "enabled": enabled,
                "mode": "once"
            ])
            await refresh()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    func signOut() async {
        await APIClient.shared.logout()
        bootstrap = nil
        refreshError = nil
        statusMessage = nil
        searchText = ""
        providerFilter = "all"
        selectedScope = .all
        selectedGroup = nil
        locatingRefs.removeAll()
        notificationRefs.removeAll()
        connectionState = .disconnected
    }
}

