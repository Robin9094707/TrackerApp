import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable { case restoring, disconnected, connecting, needsTwoFactor, connected }

    private var locationMonitors: [String: Task<Void, Never>] = [:]
    private var catalogTask: Task<[Tracker], Error>?
    private var trackerRevision = 0
    var isRefreshingTrackers = false
    private let preferences: UserDefaults
    private var sessionGeneration = UUID()
    var connectionState: ConnectionState = .restoring
    var bootstrap: BootstrapResponse?
    var isRefreshing = false
    var locatingRefs: Set<String> = []
    var notificationRefs: Set<String> = []
    var errorMessage: String?
    var lastRefresh: Date?
    var refreshError: String?
    var statusMessage: String?
    var selectedScope: TrackerScope = .all { didSet { preferences.set(selectedScope.rawValue, forKey: "tracker.scope") } }
    var selectedSort: TrackerSort = .favorites { didSet { preferences.set(selectedSort.rawValue, forKey: "tracker.sort") } }
    var selectedGroup: String? { didSet { preferences.set(selectedGroup, forKey: "tracker.group") } }
    var updatingRefs: Set<String> = []
    var isLocatingAll = false
    let locationService = LocationService()
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var username: String = UserDefaults.standard.string(forKey: "username") ?? ""
    var providerFilter = "all" { didSet { preferences.set(providerFilter, forKey: "tracker.provider") } }
    var searchText = ""

    var trackers: [Tracker] { bootstrap?.trackers ?? [] }
    var filteredTrackers: [Tracker] {
        TrackerQuery(text: searchText, provider: providerFilter, scope: selectedScope,
                     sort: selectedSort, group: selectedGroup)
            .apply(to: trackers, origin: locationService.location)
    }


    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        selectedSort = TrackerSort(rawValue: preferences.string(forKey: "tracker.sort") ?? "") ?? .favorites
        selectedScope = TrackerScope(rawValue: preferences.string(forKey: "tracker.scope") ?? "") ?? .all
        let provider = preferences.string(forKey: "tracker.provider") ?? "all"
        providerFilter = ["all", "apple", "google", "samsung", "fusion"].contains(provider) ? provider : "all"
        selectedGroup = preferences.string(forKey: "tracker.group")
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
        locationMonitors.values.forEach { $0.cancel() }; locationMonitors.removeAll()
        catalogTask?.cancel(); catalogTask = nil
        APIClient.shared.clearHistoryCache()
        sessionGeneration = UUID()
        isRefreshing = false; isRefreshingTrackers = false; isLocatingAll = false
        locatingRefs.removeAll()
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
        let generation = sessionGeneration
        let revision = trackerRevision
        defer { if generation == sessionGeneration { isRefreshing = false } }
        do {
            var data = try await APIClient.shared.bootstrap()
            guard connectionState == .connected, generation == sessionGeneration else { return }
            let alertKey = "lastAlertTimestamp:\(APIClient.shared.baseURL?.absoluteString ?? serverURL):\(data.session?.user?.id ?? username)"
            let previousTimestamp = UserDefaults.standard.integer(forKey: alertKey)
            if revision != trackerRevision, let current = bootstrap?.trackers { data.trackers = current }
            bootstrap = data
            lastRefresh = Date()
            refreshError = nil
            let events = data.alerts?.events ?? []
            if previousTimestamp > 0, data.push?.serverConfigured != true {
                for event in events.filter({ ($0.ts ?? 0) > previousTimestamp }).reversed() {
                    await PushManager.shared.scheduleLocal(event: event)
                }
            }
            let newest = events.compactMap(\.ts).max() ?? previousTimestamp
            UserDefaults.standard.set(newest, forKey: alertKey)
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

    func refreshTrackers() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        guard connectionState == .connected else { return }
        if bootstrap == nil { await refresh(); return }
        if let task = catalogTask { _ = try? await task.value; return }
        let generation = sessionGeneration
        let revision = trackerRevision
        let task = Task { try await APIClient.shared.trackerCatalog() }
        catalogTask = task; isRefreshingTrackers = true
        defer { if generation == sessionGeneration { catalogTask = nil; isRefreshingTrackers = false } }
        do {
            let items = try await task.value
            guard generation == sessionGeneration, connectionState == .connected else { return }
            if revision == trackerRevision { bootstrap?.trackers = items; trackerRevision += 1 }
            lastRefresh = Date(); refreshError = nil
        } catch is CancellationError { } catch { refreshError = error.localizedDescription }
    }

    private func updateTracker(_ tracker: Tracker) {
        if let index = bootstrap?.trackers.firstIndex(where: { $0.ref == tracker.ref }) { bootstrap?.trackers[index] = tracker; trackerRevision += 1 }
    }

    func locate(_ tracker: Tracker) async {
        guard !locatingRefs.contains(tracker.ref), !isLocatingAll else { return }
        locatingRefs.insert(tracker.ref)
        let generation = sessionGeneration
        do {
            Haptics.impact()
            _ = try await APIClient.shared.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["tracker": tracker.ref])
            guard generation == sessionGeneration else { return }
            statusMessage = "Ortung für \(tracker.name) angefordert. Warte auf eine neue Meldung …"
            locationMonitors[tracker.ref] = Task { [weak self] in
                guard let self else { return }
                defer { if self.sessionGeneration == generation { self.locatingRefs.remove(tracker.ref); self.locationMonitors[tracker.ref] = nil } }
                for delay in [1, 2, 3, 5, 8, 12, 15] {
                    do {
                        try await Task.sleep(for: .seconds(delay))
                        guard self.sessionGeneration == generation, self.connectionState == .connected else { return }
                        let updated = try await APIClient.shared.tracker(reference: tracker.ref)
                        guard self.sessionGeneration == generation, !Task.isCancelled else { return }
                        self.updateTracker(updated)
                        if updated.reportTimestamp > tracker.reportTimestamp {
                            self.statusMessage = "Neuer Standort für \(tracker.name) empfangen."; Haptics.success(); return
                        }
                    } catch is CancellationError { return }
                    catch { self.statusMessage = "Ortung angefordert, Abruf fehlgeschlagen: \(error.localizedDescription)"; return }
                }
                self.statusMessage = "Noch keine neuere Meldung für \(tracker.name). Die Serverortung läuft unabhängig weiter."
            }
        } catch { guard generation == sessionGeneration else { return }; locatingRefs.remove(tracker.ref); errorMessage = error.localizedDescription; Haptics.warning() }
    }

    func locateAll() async {
        guard !isLocatingAll, locatingRefs.isEmpty else { return }
        isLocatingAll = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isLocatingAll = false } }
        do {
            let result = try await APIClient.shared.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["all": true])
            guard generation == sessionGeneration, connectionState == .connected else { return }
            statusMessage = "Ortung für \(result["count"].integer) Objekte angefordert. Neue Meldungen erscheinen automatisch."
            Haptics.impact()
            locationMonitors["all"]?.cancel()
            locationMonitors["all"] = Task { [weak self] in
                guard let self else { return }
                defer { if self.sessionGeneration == generation { self.locationMonitors["all"] = nil } }
                for delay in [2, 4, 8, 15] {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard generation == self.sessionGeneration else { return }
                    await self.refreshTrackers()
                }
            }
        } catch { errorMessage = error.localizedDescription; Haptics.warning() }
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
            trackerRevision += 1
            Haptics.success()
        } catch { errorMessage = error.localizedDescription }
    }

    func runAction(_ action: String, payload: [String: Any]) async throws {
        _ = try await APIClient.shared.action(action, payload: payload)
        APIClient.shared.clearHistoryCache()
        if let reference = payload["tracker"] as? String {
            if let tracker = try? await APIClient.shared.tracker(reference: reference) { updateTracker(tracker) }
        } else { await refresh() }
        Haptics.success()
    }

    func foregroundUpdates() async {
        var cycle = 0
        while !Task.isCancelled {
            guard connectionState == .connected else { return }
            if cycle % 4 == 0 { await refresh() } else { await refreshTrackers() }
            cycle += 1
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
        locationMonitors.values.forEach { $0.cancel() }; locationMonitors.removeAll()
        catalogTask?.cancel(); catalogTask = nil
        APIClient.shared.clearHistoryCache()
        sessionGeneration = UUID()
        isRefreshing = false; isRefreshingTrackers = false; isLocatingAll = false
        locatingRefs.removeAll()
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

