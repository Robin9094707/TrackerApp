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
    var errorMessage: String?
    var lastRefresh: Date?
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var username: String = UserDefaults.standard.string(forKey: "username") ?? ""
    var providerFilter = "all"
    var searchText = ""

    var trackers: [Tracker] { bootstrap?.trackers ?? [] }
    var filteredTrackers: [Tracker] {
        trackers.filter { tracker in
            let providerOK = providerFilter == "all" || tracker.provider == providerFilter
            let searchOK = searchText.isEmpty || tracker.name.localizedCaseInsensitiveContains(searchText) || tracker.ref.localizedCaseInsensitiveContains(searchText)
            return providerOK && searchOK
        }
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
        await PushManager.shared.requestAuthorization()
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
        errorMessage = nil; connectionState = .connecting
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
            await refresh(); await PushManager.shared.registerIfPossible(); Haptics.success()
        } catch { errorMessage = error.localizedDescription; Haptics.warning() }
    }

    func refresh() async {
        guard connectionState == .connected, !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        do {
            let previousTimestamp = UserDefaults.standard.integer(forKey: "lastAlertTimestamp")
            let data = try await APIClient.shared.bootstrap()
            bootstrap = data
            lastRefresh = Date()
            errorMessage = nil
            let events = data.alerts?.events ?? []
            if data.push?.serverConfigured != true {
                for event in events.filter({ ($0.ts ?? 0) > previousTimestamp }).reversed() {
                    await PushManager.shared.scheduleLocal(event: event)
                }
            }
            let newest = events.compactMap(\.ts).max() ?? previousTimestamp
            UserDefaults.standard.set(newest, forKey: "lastAlertTimestamp")
            DebugLogger.shared.log("Bootstrap loaded: \(data.trackers.count) trackers")
        } catch {
            errorMessage = error.localizedDescription
            DebugLogger.shared.log("Refresh failed: \(error.localizedDescription)")
        }
    }

    func isLocating(_ tracker: Tracker) -> Bool {
        locatingRefs.contains(tracker.ref)
    }

    func locate(_ tracker: Tracker) async {
        guard !locatingRefs.contains(tracker.ref) else { return }
        locatingRefs.insert(tracker.ref)
        let oldTimestamp = tracker.location?.timestamp ?? tracker.lastSeenTs ?? 0
        defer { locatingRefs.remove(tracker.ref) }

        do {
            Haptics.impact()
            _ = try await APIClient.shared.action("locate", payload: ["tracker": tracker.ref])
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 1_250_000_000)
                await refresh()
                let updated = trackers.first(where: { $0.ref == tracker.ref })
                let newTimestamp = updated?.location?.timestamp ?? updated?.lastSeenTs ?? 0
                if newTimestamp > oldTimestamp { break }
            }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    func locateAll() async {
        let refs = Set(trackers.map(\.ref))
        locatingRefs.formUnion(refs)
        defer { locatingRefs.subtract(refs) }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/mobile/v1/locate", method: "POST", json: ["all": true])
            Haptics.impact()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    func signOut() async {
        await APIClient.shared.logout()
        bootstrap = nil
        locatingRefs.removeAll()
        connectionState = .disconnected
    }
}
