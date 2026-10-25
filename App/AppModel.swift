import Foundation
import Observation
import Combine
import SpotIntegration
import UserNotifications

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable { case restoring, disconnected, connecting, needsTwoFactor, connected }

    private var locationMonitors: [String: Task<Void, Never>] = [:]
    private var catalogTask: Task<[Tracker], Error>?
    private var trackerRevision = 0
    var isRefreshingTrackers = false
    var isRefreshingAlerts = false
    private let api: APIClient
    private let preferences: UserDefaults
    private var restoringServer = false
    private var sessionGeneration = UUID()
    var connectionState: ConnectionState = .restoring
    var bootstrap: BootstrapResponse? { didSet { mergeTrackers() } }
    private var cachedServerTrackers: [Tracker] = [] { didSet { mergeTrackers() } }
    private var hasCachedCatalog = false
    private var cacheIdentity: String { serverURL.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + username }
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

    var localGoogleTrackers: [Tracker] = [] { didSet { mergeTrackers() } }
    var showingServerConnection = false
    var localGoogleFallbackEnabled = true { didSet { preferences.set(localGoogleFallbackEnabled, forKey: "native.googleFallbackEnabled") } }
    var serverReconnectEnabled = true { didSet { preferences.set(serverReconnectEnabled, forKey: "native.serverReconnectEnabled") } }
    var showsGoogleControls: Bool { providerFilter == "all" || providerFilter == "google" }
    var serverActionsAvailable: Bool { connectionState == .connected && refreshError == nil }
    func showsMainInterface(localGoogleCredentials: Bool) -> Bool {
        connectionState == .connected || hasCachedCatalog ||
            (connectionState == .restoring && serverReconnectEnabled && !serverURL.isEmpty && !username.isEmpty) ||
            (localGoogleCredentials && localGoogleFallbackEnabled)
    }
    func useLocalGoogle() {
        localGoogleFallbackEnabled = true
        providerFilter = "google"; selectedScope = .all; selectedGroup = nil; searchText = ""
        showingServerConnection = false
    }
    @ObservationIgnored private var googleSubscriptions = Set<AnyCancellable>()
    private(set) var trackers: [Tracker] = []
    private func mergeTrackers() {
        var result = bootstrap?.trackers ?? cachedServerTrackers
        let googleIndices = Dictionary(result.enumerated().filter { $0.element.provider == "google" }
            .map { ($0.element.apiID, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for local in localGoogleTrackers {
            if let index = googleIndices[local.apiID] {
                if local.reportTimestamp >= result[index].reportTimestamp, local.location != nil { result[index].location = local.location; result[index].lastSeenTs = local.lastSeenTs }
                if let favorite = GoogleTrackerStore.shared.favoriteOverride(local.apiID) { result[index].favorite = favorite }
                result[index].battery = local.battery ?? result[index].battery
            } else { result.append(local) }
        }
        if result != trackers { trackers = result }
    }
    private func receiveGoogle(_ snapshots: [GoogleTrackerSnapshot]) {
        localGoogleTrackers = snapshots.map { snapshot in
            let location: TrackerLocation? = {
                guard let lat = snapshot.latitude, let lon = snapshot.longitude else { return nil }
                return TrackerLocation(latitude: lat, longitude: lon, accuracyM: snapshot.accuracy,
                    timestamp: snapshot.reportedAt.map { Int($0.timeIntervalSince1970) }, network: "google", provider: "google")
            }()
            return Tracker(ref: "google:" + snapshot.id, name: snapshot.name, provider: "google", location: location,
                lastSeenTs: snapshot.reportedAt.map { Int($0.timeIntervalSince1970) }, battery: snapshot.battery,
                status: snapshot.nearby ? "In der Nähe" : "Google direkt", favorite: GoogleTrackerStore.shared.favorite(snapshot.id),
                historyActive: snapshot.historyEnabled, emoji: "📡", serverID: snapshot.id)
        }
    }
    var filteredTrackers: [Tracker] {
        TrackerQuery(text: searchText, provider: providerFilter, scope: selectedScope,
                     sort: selectedSort, group: selectedGroup)
            .apply(to: trackers, origin: locationService.location)
    }


    init(preferences: UserDefaults = .standard, api: APIClient? = nil) {
        self.preferences = preferences
        self.api = api ?? .shared
        // A legacy native.localMode=false selected the server UI, not a ban on fallback.
        localGoogleFallbackEnabled = preferences.object(forKey: "native.googleFallbackEnabled") as? Bool ?? true
        serverReconnectEnabled = preferences.object(forKey: "native.serverReconnectEnabled") as? Bool ?? true
        GoogleTrackerStore.shared.$trackers.receive(on: DispatchQueue.main).sink { [weak self] snapshots in
            Task { @MainActor in self?.receiveGoogle(snapshots) }
        }.store(in: &googleSubscriptions)
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
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-local-google") {
                GoogleTrackerStore.shared.useUITestState()
                connectionState = ProcessInfo.processInfo.arguments.contains("--ui-testing-restoring") ? .restoring : .disconnected
                refreshError = "Testserver nicht erreichbar"
            } else { connectionState = .connected; lastRefresh = Date() }
            return
        }
        #endif
        let identity = cacheIdentity
        let generation = sessionGeneration
        if serverReconnectEnabled, !serverURL.isEmpty,
           let snapshot = await TrackerStartupCache.shared.load(identity: identity),
           identity == cacheIdentity, generation == sessionGeneration {
            cachedServerTrackers = snapshot.trackers
            lastRefresh = snapshot.date
            hasCachedCatalog = true
        }
        await retryServerConnection()
    }

    private func saveCatalog() async {
        guard let bootstrap else { return }
        await TrackerStartupCache.shared.save(bootstrap.trackers, date: lastRefresh ?? Date(), identity: cacheIdentity)
    }
    private func clearCatalog() async {
        hasCachedCatalog = false; cachedServerTrackers = []
        await TrackerStartupCache.shared.clear(identity: cacheIdentity)
    }

    func retryServerConnection() async {
        guard !restoringServer else { return }
        guard serverReconnectEnabled, !serverURL.isEmpty else { connectionState = .disconnected; return }
        let generation = sessionGeneration
        restoringServer = true
        defer { restoringServer = false }
        do {
            try self.api.configure(server: serverURL)
            let session = try await self.api.session()
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            if session.authenticated == true {
                connectionState = .connected
                refreshError = nil
                await refresh()
                await PushManager.shared.registerIfPossible()
            } else { await clearCatalog(); connectionState = .disconnected }
        } catch {
            guard generation == sessionGeneration else { return }
            if case APIError.http(401, _) = error { await clearCatalog() }
            refreshError = error.localizedDescription
            connectionState = .disconnected
            DebugLogger.shared.log("Server restoration failed: \(error.localizedDescription)")
        }
    }

    func connect(password: String) async {
        await clearCatalog()
        bootstrap = nil
        serverReconnectEnabled = true
        locationMonitors.values.forEach { $0.cancel() }; locationMonitors.removeAll()
        catalogTask?.cancel(); catalogTask = nil
        self.api.clearHistoryCache()
        sessionGeneration = UUID()
        isRefreshing = false; isRefreshingTrackers = false; isRefreshingAlerts = false; isLocatingAll = false
        locatingRefs.removeAll()
        errorMessage = nil
        connectionState = .connecting
        do {
            let result = try await self.api.pair(server: serverURL, username: username, password: password)
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
            let result = try await self.api.pair2FA(code: code)
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
            var data = try await self.api.bootstrap()
            guard connectionState == .connected, generation == sessionGeneration else { return }
            let alertKey = "lastAlertTimestamp:\(self.api.baseURL?.absoluteString ?? serverURL):\(data.session?.user?.id ?? username)"
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
            await saveCatalog()
        } catch is CancellationError {
            return
        } catch {
            refreshError = error.localizedDescription
            DebugLogger.shared.log("Refresh failed: \(error.localizedDescription)")
        }
    }

    func isLocating(_ tracker: Tracker) -> Bool {
        locatingRefs.contains(tracker.ref) || (tracker.provider == "google" && GoogleTrackerStore.shared.locating.contains(tracker.apiID))
    }
    func isUpdatingNotification(_ tracker: Tracker) -> Bool { notificationRefs.contains(tracker.ref) }

    func refreshAlerts(limit: Int = 150, unreadOnly: Bool = false) async {
        guard connectionState == .connected, !isRefreshingAlerts else { return }
        if bootstrap == nil { await refresh(); return }
        let generation = sessionGeneration
        isRefreshingAlerts = true
        defer { if generation == sessionGeneration { isRefreshingAlerts = false } }
        do {
            let alerts = try await self.api.alerts(limit: limit, unreadOnly: unreadOnly)
            guard generation == sessionGeneration, connectionState == .connected, !Task.isCancelled else { return }
            bootstrap?.alerts = alerts
            try? await UNUserNotificationCenter.current().setBadgeCount(alerts.unreadCount ?? 0)
        } catch is CancellationError { } catch {
            guard generation == sessionGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshTrackers() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        guard connectionState == .connected else { return }
        if bootstrap == nil { await refresh(); return }
        if let task = catalogTask { _ = try? await task.value; return }
        let generation = sessionGeneration
        let revision = trackerRevision
        let task = Task { try await self.api.trackerCatalog() }
        catalogTask = task; isRefreshingTrackers = true
        defer { if generation == sessionGeneration { catalogTask = nil; isRefreshingTrackers = false } }
        do {
            let items = try await task.value
            guard generation == sessionGeneration, connectionState == .connected else { return }
            if revision == trackerRevision { bootstrap?.trackers = items; trackerRevision += 1 }
            lastRefresh = Date(); refreshError = nil
            await saveCatalog()
        } catch is CancellationError { } catch { refreshError = error.localizedDescription }
    }

    private func updateTracker(_ tracker: Tracker) {
        if let index = bootstrap?.trackers.firstIndex(where: { $0.ref == tracker.ref }) { bootstrap?.trackers[index] = tracker; trackerRevision += 1 }
    }

    func locate(_ tracker: Tracker) async {
        if tracker.provider == "google", GoogleTrackerStore.shared.hasDevice(tracker.apiID) {
            do { try GoogleTrackerStore.shared.locate(tracker.apiID); statusMessage = "Google sammelt alle Reports für \(tracker.name) …" }
            catch { errorMessage = error.localizedDescription }
            return
        }
        guard !locatingRefs.contains(tracker.ref), !isLocatingAll else { return }
        locatingRefs.insert(tracker.ref)
        let generation = sessionGeneration
        do {
            Haptics.impact()
            _ = try await self.api.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["tracker": tracker.ref])
            guard generation == sessionGeneration else { return }
            statusMessage = "Ortung für \(tracker.name) angefordert. Warte auf eine neue Meldung …"
            locationMonitors[tracker.ref] = Task { [weak self] in
                guard let self else { return }
                defer { if self.sessionGeneration == generation { self.locatingRefs.remove(tracker.ref); self.locationMonitors[tracker.ref] = nil } }
                for delay in [1, 2, 3, 5, 8, 12, 15] {
                    do {
                        try await Task.sleep(for: .seconds(delay))
                        guard self.sessionGeneration == generation, self.connectionState == .connected else { return }
                        let updated = try await self.api.tracker(reference: tracker.ref)
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
        GoogleTrackerStore.shared.requestReportsForAll(automatic: false)
        if connectionState != .connected { return }
        guard !isLocatingAll, locatingRefs.isEmpty else { return }
        isLocatingAll = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { isLocatingAll = false } }
        do {
            let result = try await self.api.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["all": true])
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
        if tracker.provider == "google", GoogleTrackerStore.shared.hasDevice(tracker.apiID) {
            GoogleTrackerStore.shared.setFavorite(tracker.apiID, enabled: tracker.favorite != true)
            receiveGoogle(GoogleTrackerStore.shared.trackers)
            return
        }
        guard !updatingRefs.contains(tracker.ref) else { return }
        updatingRefs.insert(tracker.ref)
        defer { updatingRefs.remove(tracker.ref) }
        let newValue = tracker.favorite != true
        do {
            _ = try await self.api.requestJSON(
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
        _ = try await self.api.action(action, payload: payload)
        self.api.clearHistoryCache()
        if let reference = payload["tracker"] as? String {
            if let tracker = try? await self.api.tracker(reference: reference) { updateTracker(tracker) }
        } else { await refresh() }
        Haptics.success()
    }

    func foregroundUpdates() async {
        var cycle = 0
        while !Task.isCancelled {
            if connectionState == .connected {
                if cycle % 6 == 0 { await refresh() } else { await refreshTrackers() }
            } else if connectionState == .disconnected, serverReconnectEnabled, !serverURL.isEmpty {
                await retryServerConnection()
            }
            cycle += 1
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
        }
    }

    func setFoundNotification(_ tracker: Tracker, enabled: Bool) async {
        guard !notificationRefs.contains(tracker.ref) else { return }
        notificationRefs.insert(tracker.ref)
        defer { notificationRefs.remove(tracker.ref) }
        do {
            _ = try await self.api.action("set_found_notification", payload: [
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
        serverReconnectEnabled = false
        locationMonitors.values.forEach { $0.cancel() }; locationMonitors.removeAll()
        catalogTask?.cancel(); catalogTask = nil
        self.api.clearHistoryCache()
        sessionGeneration = UUID()
        isRefreshing = false; isRefreshingTrackers = false; isRefreshingAlerts = false; isLocatingAll = false
        locatingRefs.removeAll()
        await clearCatalog()
        await self.api.logout()
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

