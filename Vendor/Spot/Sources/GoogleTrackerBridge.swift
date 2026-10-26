// Native protocol service extracted from Spot (Leon Böttger), GPL-3.0-only.
// Contains no application root, onboarding, navigation or other app's screens.
import Foundation
import Combine
import CoreBluetooth
import WebKit

final class SpotResourceMarker: NSObject {}

public struct GoogleTrackerSnapshot: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let imageURL: String
    public let latitude: Double?
    public let longitude: Double?
    public let accuracy: Double?
    public let reportedAt: Date?
    public let nearby: Bool
    public let battery: String?
    public let reportCount: Int
    public let historyEnabled: Bool
    public let unlocked: Bool
    public let isLost: Bool
    public let sharedWith: [String]
    public let signal: Double?
}
public struct GoogleReportSnapshot: Identifiable, Equatable {
    public let id: String
    public let date: Date
    public let latitude: Double?
    public let longitude: Double?
    public let accuracy: Double?
    public let kind: String
    public let own: Bool
    public let label: String?
}

@MainActor public final class GoogleTrackerStore: ObservableObject {
    public static let shared = GoogleTrackerStore()
    @Published public private(set) var trackers: [GoogleTrackerSnapshot] = []
    @Published public private(set) var account: String?
    @Published public private(set) var hasCredentials = false
    @Published public private(set) var needsKeys = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var locating: Set<String> = []
    @Published public private(set) var locationStatus: [String: String] = [:]
    @Published public private(set) var locationSucceeded: [String: Bool] = [:]
    private var locationRequests = GoogleLocationRequests()
    @Published public var refreshInterval: Int {
        didSet { preferences.set(Self.validInterval(refreshInterval), forKey: "native.refreshInterval"); restartPolling() }
    }
    @Published public var contributorMode: String {
        didSet {
            preferences.set(contributorMode, forKey: "native.contributorMode")
            Settings.sharedInstance.contributorType = ContributorType(rawValue: contributorMode) ?? .AtAllAreas
        }
    }
    private let preferences = UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!
    private var subscriptions = Set<AnyCancellable>()
    private var deviceSubscriptions = Set<AnyCancellable>()
    private var polling: Task<Void, Never>?
    private var active = true
    private var restored = false
    private var generation = UUID()
    private var uwbProbes = Set<String>()
    @Published public private(set) var firmwareDeviceID: String?
    @Published public var backgroundHistoryEnabled: Bool {
        didSet { preferences.set(backgroundHistoryEnabled, forKey: "native.backgroundHistoryEnabled") }
    }
    #if DEBUG
    private var uiTestState = false
    #endif
    private var lastReportRequest = Date.distantPast
    private var lastCatalog = Date.distantPast
    private var lastMaintenance = Date.distantPast
    nonisolated public static func validInterval(_ value: Int) -> Int { [0, 60, 120, 300, 900].contains(value) ? value : 60 }

    private init() {
        backgroundHistoryEnabled = preferences.bool(forKey: "native.backgroundHistoryEnabled")
        refreshInterval = Self.validInterval(preferences.object(forKey: "native.refreshInterval") as? Int ?? 60)
        contributorMode = preferences.string(forKey: "native.contributorMode") ?? "AtAllAreas"
        Settings.sharedInstance.contributorType = ContributorType(rawValue: contributorMode) ?? .AtAllAreas
    }
    private func startObserving() {
        guard subscriptions.isEmpty else { publishSnapshots(); return }
        Settings.sharedInstance.$devicesList.receive(on: DispatchQueue.main).sink { [weak self] devices in
            guard let self else { return }
            self.deviceSubscriptions.removeAll()
            for device in devices ?? [] {
                device.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
                    DispatchQueue.main.async { self?.publishSnapshots() }
                }.store(in: &self.deviceSubscriptions)
            }
            DispatchQueue.main.async { self.publishSnapshots() }
        }.store(in: &subscriptions)
        TokenManager.sharedInstance.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.publishSnapshots() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .googleEngineError).receive(on: DispatchQueue.main).sink { [weak self] notification in
            self?.errorMessage = notification.userInfo?["message"] as? String
        }.store(in: &subscriptions)
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.publishSnapshots() }.store(in: &subscriptions)
        publishSnapshots()
    }
    public func clearError() { errorMessage = nil }
    public func hasDevice(_ id: String) -> Bool { trackers.contains { $0.id == id } }
    public func favoriteOverride(_ id: String) -> Bool? { preferences.object(forKey: favoriteKey(id)) as? Bool }
    public func favorite(_ id: String) -> Bool { preferences.bool(forKey: favoriteKey(id)) }
    public func setFavorite(_ id: String, enabled: Bool) { preferences.set(enabled, forKey: favoriteKey(id)); objectWillChange.send() }
    private func favoriteKey(_ id: String) -> String { "native.favorite." + SHA256.hash(data: Data(((account ?? "") + id).utf8)).hex }
    private func device(_ id: String) throws -> LocalFindMyDevice {
        guard firmwareDeviceID != id else { throw googleError("Der Moto Tag wird gerade für ein Firmwareupdate verwendet.") }
        guard let device = Settings.sharedInstance.devicesList?.first(where: { $0.id == id }), device.belongsToCurrentAccount else { throw googleError("Google-Tracker ist noch nicht geladen.") }
        return device
    }
    public func reports(for id: String) async -> [GoogleReportSnapshot] {
        guard let device = try? device(id) else { return [] }
        let refreshes = device.refreshes
        let token = generation
        let result = await Task.detached(priority: .userInitiated) {
            uniqueGoogleReports(refreshes.flatMap(\.reports)).map { report in
            let location = report.decryptedLocation
            return GoogleReportSnapshot(id: googleReportIdentity(report), date: report.time,
                latitude: location?.latitude, longitude: location?.longitude, accuracy: report.accuracy.map(Double.init),
                kind: String(describing: report.status), own: report.isOwnReport, label: report.name)
            }
        }.value
        guard !Task.isCancelled, token == generation, device.belongsToCurrentAccount else { return [] }
        return result
    }
    public func setHistoryEnabled(_ id: String, enabled: Bool) {
        guard let account, hasDevice(id) else { return }
        GoogleCollectionPreferences.set(enabled, account: account, deviceID: id, defaults: preferences)
        publishSnapshots()
        if enabled, refreshInterval > 0 { try? locate(id) }
    }
    private var snapshotTask: Task<Void, Never>?
    private var snapshotsDirty = false
    private var reportSummaries: [String: (revision: UUID, latest: LocationReportWrapper?, count: Int)] = [:]
    private func publishSnapshots() {
        #if DEBUG
        if uiTestState { return }
        #endif
        let manager = TokenManager.sharedInstance
        let newAccount = manager.username
        if account != newAccount { account = newAccount; reportSummaries.removeAll() }
        let authenticated = manager.aasToken != nil
        if hasCredentials != authenticated { hasCredentials = authenticated }
        let locked = authenticated && manager.ownerKey == nil
        if needsKeys != locked { needsKeys = locked }
        guard hasCredentials else {
            snapshotsDirty = false
            if !trackers.isEmpty { trackers = [] }
            reportSummaries.removeAll()
            return
        }
        snapshotsDirty = true
        guard snapshotTask == nil else { return }
        // Combine emits before mutation. Coalesce a burst of metadata/Bluetooth changes,
        // then hash and sort immutable report copies on a worker, never the UI thread.
        snapshotTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self else { return }
            while self.snapshotsDirty && self.hasCredentials && !Task.isCancelled {
                self.snapshotsDirty = false
                await self.rebuildSnapshots()
                await Task.yield()
            }
            self.snapshotTask = nil
        }
    }
    private func rebuildSnapshots() async {
        let token = generation
        var snapshots: [GoogleTrackerSnapshot] = []
        let devices = (Settings.sharedInstance.devicesList ?? []).filter(\.belongsToCurrentAccount)
        let validIDs = Set(devices.map(\.id))
        reportSummaries = reportSummaries.filter { validIDs.contains($0.key) }
        for device in devices {
            let revision = device.reportRevision
            if reportSummaries[device.id]?.revision != revision {
                let refreshes = device.refreshes
                let summary = await Task.detached(priority: .utility) {
                    let reports = uniqueGoogleReports(refreshes.flatMap(\.reports))
                    return (reports.first { $0.decryptedLocation != nil }, reports.count)
                }.value
                guard !Task.isCancelled, token == generation, device.belongsToCurrentAccount,
                      device.reportRevision == revision else { return }
                reportSummaries[device.id] = (revision, summary.0, summary.1)
            }
            let summary = reportSummaries[device.id]
            let report = summary?.latest
            let location = report?.decryptedLocation
            let nearby = device.bluetoothData.map { !deviceNotCurrentlyReachable(device: $0, currentDate: Date()) } ?? false
            snapshots.append(GoogleTrackerSnapshot(id: device.id, name: device.userDefinedName, imageURL: device.imageURL,
                latitude: location?.latitude, longitude: location?.longitude, accuracy: report?.accuracy.map(Double.init),
                reportedAt: report?.time, nearby: nearby, battery: device.batteryState == .Unknown ? nil : device.batteryState.rawValue,
                reportCount: summary?.count ?? 0, historyEnabled: GoogleCollectionPreferences.enabled(account: account ?? "", deviceID: device.id, defaults: preferences), unlocked: device.eik != nil, isLost: device.isLost,
                sharedWith: device.sharingSettings.usersWithAccess, signal: nearby ? device.bluetoothData?.rssi_publisher : nil))
        }
        guard !Task.isCancelled, token == generation else { return }
        if snapshots != trackers { trackers = snapshots }
    }
    public func restoreIfNeeded() async {
        #if DEBUG
        if uiTestState { return }
        #endif
        guard !restored else { return }; restored = true
        // Keychain and persisted protobuf catalogs may take time after a cold launch.
        // Prepare them off the main actor while the first frame becomes interactive.
        await Task.detached(priority: .userInitiated) { _ = TokenManager.sharedInstance.aasToken; _ = TokenManager.sharedInstance.ownerKey }.value
        startObserving()
        let token = generation
        if hasCredentials {
            let cached = await Task.detached(priority: .userInitiated) { GoogleReportArchive.catalog() }.value
            guard token == generation else { return }
            if let cached { await Task.detached(priority: .userInitiated) { await processDeviceList(list: cached.deviceMetadata) }.value }
            await refresh()
        } else {
            // Recover a completed Google web login whose final token exchange was interrupted.
            let cookies: [HTTPCookie] = (try? await googleCallback(seconds: 5) { done in
                CookieCache.getAllCookies { done(.success($0)) }
            }) ?? []
            if let cookie = cookies.first(where: { Self.isOAuthCookie($0) }) {
                do { try await finishLogin(oauthToken: cookie.value) } catch { errorMessage = error.localizedDescription }
            }
        }
        restartPolling()
    }
    nonisolated public static func isOAuthCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.name == "oauth_token" && ["accounts.google.com", ".google.com", "google.com"].contains(cookie.domain)
    }
    public func prepareLogin() async throws -> URL {
        guard firmwareDeviceID == nil else { throw googleError("Bitte zuerst die Motorola-Aktualisierung beenden.") }
        statusMessage = "Google-Verbindung vorbereiten …"
        defer { statusMessage = nil }
        try await PushReceiver.sharedInstance.prepare()
        return URL(string: "https://accounts.google.com/EmbeddedSetup")!
    }
    public func finishLogin(oauthToken: String) async throws {
        guard firmwareDeviceID == nil else { throw googleError("Bitte zuerst die Motorola-Aktualisierung beenden.") }
        try await PushReceiver.sharedInstance.prepare()
        guard let id = PushReceiver.sharedInstance.getAndroidId() else { throw googleError("Google-Geräteregistrierung fehlt. Bitte erneut versuchen.") }
        let response: [String: String] = try await googleCallback { done in
            PlayServicesOAuth.requestAASToken(email: TokenManager.sharedInstance.username ?? "", oauthToken: oauthToken, androidID: String(id), completion: done)
        }
        guard let token = response["Token"], !token.isEmpty,
              let email = response["Email"] ?? TokenManager.sharedInstance.username, email.contains("@") else {
            throw googleError("Google hat den Zugang noch nicht bestätigt. Bitte die Anmeldung erneut abschließen.")
        }
        let manager = TokenManager.sharedInstance
        let changed = manager.username?.lowercased() != email.lowercased()
        try KeychainStore.shared.save(token, for: .aasToken)
        if changed {
            manager.ownerKey = nil; manager.sharedKey = nil
            Settings.sharedInstance.devicesList = nil; generation = UUID(); locating.removeAll(); locationRequests.reset(); locationStatus.removeAll(); locationSucceeded.removeAll()
        }
        manager.clearCachedTokens(); manager.username = email; manager.aasToken = token
        publishSnapshots()
        Task { await self.refresh(); self.restartPolling() }
        CookieCache.removeOAuthCookie(value: oauthToken)
    }

    public func refresh(requestLocations: Bool = true) async {
        #if DEBUG
        if uiTestState { return }
        #endif
        guard !isRefreshing, hasCredentials else { return }
        isRefreshing = true; errorMessage = nil
        let generation = self.generation
        defer { isRefreshing = false }
        do {
            try await PushReceiver.sharedInstance.prepare()
            let list = try await NovaApiManager.sharedInstance.requestDeviceList()
            guard generation == self.generation else { return }
            try await Task.detached(priority: .utility) { try GoogleReportArchive.storeCatalog(list) }.value
            guard generation == self.generation else { return }
            if TokenManager.sharedInstance.ownerKey == nil, let shared = TokenManager.sharedInstance.sharedKey?.dataFromHex {
                try? await installSharedKey(shared)
            }
            await Task.detached(priority: .userInitiated) { await processDeviceList(list: list.deviceMetadata) }.value
            // processDeviceList commits its observable list on the main queue.
            await Task.yield()
            lastCatalog = .now
            if CBManager.authorization == .allowedAlways { BluetoothManager.sharedInstance.startCentralManager() }
            let devices = Settings.sharedInstance.devicesList ?? []
            DispatchQueue.global(qos: .utility).async { GoogleReportArchive.replay(devices: devices) }
            if TokenManager.sharedInstance.ownerKey != nil, Date().timeIntervalSince(lastMaintenance) >= 900 {
                lastMaintenance = .now
                try? UploadPrecomputedPublicKeyIds.sharedInstance.checkAndUpload()
            }
            publishSnapshots()
            if requestLocations { requestReportsForAll() }
        } catch { if generation == self.generation { errorMessage = error.localizedDescription } }
    }
    public func locate(_ id: String) throws {
        let device = try device(id)
        guard let request = locationRequests.begin(id) else { return }
        locating = locationRequests.pending
        locationStatus[id] = nil
        locationSucceeded[id] = nil
        let generation = self.generation
        NovaApiManager.sharedInstance.requestLocationDataForDevice(device: device) { [weak self] success in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.publishSnapshots() // Later packets still update the map and archive.
                guard self.locationRequests.contains(id, token: request) else { return }
                if success { await self.rebuildSnapshots() }
                guard generation == self.generation,
                      self.locationRequests.finish(id, token: request) else { return }
                self.locationSucceeded[id] = success
                self.locationStatus[id] = success
                    ? "Google-Antwort empfangen. Der zuletzt gemeldete Standort wird angezeigt."
                    : "Keine Google-Antwort erhalten. Gespeicherte Standorte bleiben sichtbar. Bitte erneut versuchen."
                self.locating = self.locationRequests.pending
            }
        }
        // Safety deadline only; a real response/error clears the spinner immediately.
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(38)) } catch { return }
            guard let self, generation == self.generation,
                  self.locationRequests.finish(id, token: request) else { return }
            self.locationSucceeded[id] = false
            self.locationStatus[id] = "Noch keine Google-Antwort. Du kannst erneut aktualisieren."
            self.locating = self.locationRequests.pending
        }
    }
    public func refreshLocation(_ id: String) async {
        do { try locate(id) } catch { errorMessage = error.localizedDescription; return }
        await waitForLocations([id])
    }
    /// Manual requests include trackers with paused automatic history collection.
    /// Use the loaded catalog immediately instead of waiting for an extra list request.
    public func refreshLocations() async {
        #if DEBUG
        if uiTestState { return }
        #endif
        guard hasCredentials else { return }
        let generation = self.generation
        let loadedIDs = Set(trackers.map(\.id))
        requestReportsForAll(automatic: false)
        // Existing trackers start immediately; discover additions periodically as well.
        if trackers.isEmpty || Date().timeIntervalSince(lastCatalog) >= 300 {
            await refresh(requestLocations: false)
            guard generation == self.generation else { return }
            await rebuildSnapshots()
            for tracker in trackers where !loadedIDs.contains(tracker.id) {
                do { try locate(tracker.id) } catch { locationStatus[tracker.id] = error.localizedDescription }
            }
        }
        await waitForLocations(Set(trackers.map(\.id)))
    }
    private func waitForLocations(_ ids: Set<String>) async {
        let generation = self.generation
        while generation == self.generation, !locating.isDisjoint(with: ids) {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }
    public func requestReportsForAll(automatic: Bool = true) {
        #if DEBUG
        if uiTestState { return }
        #endif
        lastReportRequest = .now
        for tracker in trackers where !automatic || tracker.historyEnabled {
            do { try locate(tracker.id) }
            catch { locationStatus[tracker.id] = error.localizedDescription }
        }
    }
    public func sceneChanged(active: Bool) {
        self.active = active
        if hasCredentials { Settings.sharedInstance.isBackground = !active }
        restartPolling()
        if active, hasCredentials, refreshInterval > 0,
           Date().timeIntervalSince(lastReportRequest) >= Double(Self.validInterval(refreshInterval)) {
            requestReportsForAll()
        }
    }
    private func restartPolling() {
        polling?.cancel(); polling = nil
        guard active, hasCredentials, refreshInterval > 0 else { return }
        let seconds = Self.validInterval(refreshInterval)
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) } catch { return }
                guard let self, self.active else { return }
                if Date().timeIntervalSince(self.lastCatalog) > 300 { await self.refresh() }
                else { self.requestReportsForAll() }
            }
        }
    }
    public func motorolaModel(_ id: String) -> MotorolaTagModel? {
        #if DEBUG
        if uiTestState && CommandLine.arguments.contains("--ui-test-motorola") && id == "demo-local-tag" { return .firstGeneration }
        #endif
        guard let target = Settings.sharedInstance.devicesList?.first(where: { $0.id == id && $0.belongsToCurrentAccount }),
              !target.isCustomTracker else { return nil }
        return MotorolaTagModel.identify(target.fastPairModelID)
    }
    public func beginMotorolaFirmwareAccess(_ id: String) async throws -> MotorolaFirmwareTarget {
        guard firmwareDeviceID == nil else { throw googleError("Eine Motorola-Prüfung oder Aktualisierung läuft bereits.") }
        let target = try device(id)
        guard let model = motorolaModel(id), let key = target.accountKey,
              let bluetooth = target.bluetoothData, !deviceNotCurrentlyReachable(device: bluetooth, currentDate: Date()),
              let uuid = UUID(uuidString: bluetooth.identifier_background) else {
            throw googleError("Eigenen Motorola-Tag in Bluetooth-Reichweite bringen und Google-Schlüssel entsperren.")
        }
        let token = generation
        firmwareDeviceID = id
        do {
            let _: Bool = try await googleCallback(seconds: 35) { done in
                let read = BluetoothRequest.readCharacteristic(deviceID: uuid.uuidString, serviceID: Constants.FastPairService,
                    characteristicID: Constants.FastPairBeaconActionsCharacteristic, stayConnected: true) { state, authentication in
                    guard state == .Success, let authentication else { done(.failure(googleError("Moto Tag antwortet nicht auf die Authentifizierung."))); return }
                    do {
                        let packet = try MotorolaOwnerProof.request(authentication: authentication, key: key)
                        let write = BluetoothRequest.writeReadCharacteristic(deviceID: uuid.uuidString, serviceID: Constants.FastPairService,
                            characteristicID: Constants.FastPairBeaconActionsCharacteristic, data: packet) { state, response in
                            guard state == .Success, let response else { done(.failure(googleError("Eigentümerbestätigung des Moto Tag fehlt."))); return }
                            do { try MotorolaOwnerProof.verify(response, authentication: authentication, key: key); done(.success(true)) }
                            catch { done(.failure(error)) }
                        }
                        BluetoothManager.sharedInstance.addRequest(request: write)
                    } catch { done(.failure(error)) }
                }
                BluetoothManager.sharedInstance.addRequest(request: read)
            }
            guard token == generation, target.belongsToCurrentAccount else { throw CancellationError() }
            await BluetoothManager.sharedInstance.reserveForFirmware(uuid)
            return MotorolaFirmwareTarget(deviceID: id, peripheralID: uuid, model: model,
                fastPairModelID: target.fastPairModelID.lowercased(), generation: token)
        } catch { firmwareDeviceID = nil; throw error }
    }
    public func motorolaAccessIsCurrent(_ target: MotorolaFirmwareTarget) -> Bool {
        firmwareDeviceID == target.deviceID && generation == target.generation && hasCredentials
    }
    public func endMotorolaFirmwareAccess(_ target: MotorolaFirmwareTarget) {
        BluetoothManager.sharedInstance.releaseFromFirmware(target.peripheralID)
        if firmwareDeviceID == target.deviceID { firmwareDeviceID = nil }
    }
    public func probeUWBCapabilities(_ id: String) async throws -> GoogleUWBCapabilities {
        let target = try device(id)
        guard uwbProbes.insert(id).inserted else { throw googleError("Eine UWB-Prüfung läuft bereits für diesen Tracker.") }
        defer { uwbProbes.remove(id) }
        guard let bluetoothID = target.bluetoothData?.identifier_background,
              let key = target.accountKey else { throw googleError("Tracker zuerst in Bluetooth-Reichweite bringen und Google-Schlüssel entsperren.") }
        let generation = self.generation
        let result: GoogleUWBCapabilities = try await googleCallback(seconds: 35) { done in
            let read = BluetoothRequest.readCharacteristic(deviceID: bluetoothID, serviceID: Constants.FastPairService,
                characteristicID: Constants.FastPairBeaconActionsCharacteristic, stayConnected: true) { state, authentication in
                guard state == .Success, let authentication else {
                    done(.failure(googleError("Die Bluetooth-Authentifizierung hat nicht geantwortet."))); return
                }
                do {
                    let payload = try GoogleUWBProbe.request(authentication: authentication, accountKey: key)
                    let request = BluetoothRequest.writeReadCharacteristic(deviceID: bluetoothID, serviceID: Constants.FastPairService,
                        characteristicID: Constants.FastPairBeaconActionsCharacteristic, data: payload) { state, packet in
                        guard state == .Success, let packet else {
                            done(.failure(googleError("Keine bestätigte Antwort auf die experimentelle UWB-Abfrage. Das beweist nicht, dass der Tracker kein UWB hat."))); return
                        }
                        do { done(.success(try GoogleUWBProbe.response(packet, authentication: authentication, accountKey: key))) }
                        catch { done(.failure(error)) }
                    }
                    BluetoothManager.sharedInstance.addRequest(request: request)
                } catch { done(.failure(error)) }
            }
            BluetoothManager.sharedInstance.addRequest(request: read)
        }
        guard generation == self.generation, target.belongsToCurrentAccount else { throw CancellationError() }
        return result
    }
    public func beginNearby(_ id: String) {
        #if DEBUG
        if uiTestState { return }
        #endif
        BluetoothManager.sharedInstance.startCentralManager()
        let identifier = try? device(id).bluetoothData?.identifier_background
        let uuids: [UUID] = identifier.flatMap { $0 }.flatMap { UUID(uuidString: $0) }.map { [$0] } ?? []
        BluetoothManager.sharedInstance.enableFastScan(for: RSSIScan(service: Constants.FindMyDeviceService), allowedUUIDs: uuids)
    }
    public func endNearby() {
        #if DEBUG
        if uiTestState { return }
        #endif
        BluetoothManager.sharedInstance.disableFastScan()
    }
    public func repairConnection() async throws {
        guard firmwareDeviceID == nil else { throw googleError("Bitte zuerst die Motorola-Aktualisierung beenden.") }
        generation = UUID(); locating.removeAll(); locationRequests.reset(); locationStatus.removeAll(); locationSucceeded.removeAll()
        try await PushReceiver.sharedInstance.prepare(force: true)
        await refresh()
    }
    public func requestBluetooth() { BluetoothManager.sharedInstance.startCentralManager() }
    public func ring(_ id: String, stop: Bool = false) async throws {
        let device = try device(id)
        if !stop, let bluetooth = device.bluetoothData, !deviceNotCurrentlyReachable(device: bluetooth, currentDate: Date()), let eik = device.eik {
            let result: BluetoothRequestState = try await googleCallback(seconds: 15) { done in
                FMDNOwnerOperations.executeRingerOperation(currentBluetoothId: bluetooth.identifier_background, eik: eik) { state, _ in done(.success(state)) }
            }
            guard result == .Success else { throw googleError("Der Tracker hat das Bluetooth-Klingeln nicht bestätigt.") }
        } else {
            try await NovaApiManager.sharedInstance.controlSoundForDevice(canonicDeviceId: id, action: stop ? .stop : .start)
        }
    }
    public func rename(_ id: String, name: String) async throws {
        let device = try device(id)
        try await UpdateBleDevice.setDeviceInfo(canonicDeviceId: id, userDefinedName: name, imageURL: device.imageURL)
        device.userDefinedName = name; publishSnapshots()
    }
    public func setLost(_ id: String, enabled: Bool) async throws { try await UpdateBleDevice.setLostMode(canonicDeviceId: id, lostMode: enabled); try device(id).isLost = enabled; publishSnapshots() }
    public func sharingLink(_ id: String) async throws -> String { try await UpdateBleDeviceSharingSettings.createSharingLink(device: device(id)) }
    public func removeSharing(_ id: String, email: String) async throws { try await UpdateBleDeviceSharingSettings.stopSharing(canonicDeviceID: id, removedAccount: email); await refresh() }
    public func acceptInvitation(_ link: String) async throws -> String {
        let invitation = try await UpdateBleDeviceSharingSettings.retrieveInvitationFromLink(link: link)
        let pin = try await UpdateBleDeviceSharingSettings.acceptInvitation(invitation: invitation); await refresh(); return pin
    }
    public func approveSharing(_ id: String) async throws {
        let device = try device(id)
        guard let operation = device.sharingSettings.pendingShareOperations.first, let own = operation.sharingOwnPrivateKey,
              let other = operation.sharingOtherPublicKey, let eik = device.eik, let key = device.accountKey else { throw googleError("Keine ausstehende Freigabe vorhanden.") }
        try await UpdateBleDeviceSharingSettings.acceptInviteeAndUploadEncryptedKeys(canonicDeviceID: id, EIK: eik, accountKey: key,
            inviteeAccount: operation.accountName, creationDate: device.keyDate, inviteeDER: other, ownerPrivateKeyWrapper: own)
        await refresh()
    }
    public func createESP32() async throws -> String {
        guard let key = TokenManager.sharedInstance.ownerKey?.dataFromHex else { throw googleError("Bitte zuerst Google-Schlüssel entsperren.") }
        let pairDate = Date().unixTime - 600
        let keys = try RegisterBleDeviceKeyGen.generateE2EEKeys(pairDate: pairDate, curveType: .secp160r1, eidLimitSeconds: 1, isCustomTracker: true)
        _ = try await RegisterBleDevice.registerESP32(pairDate: pairDate, ownerKey: key, EIK: keys.eik, curveType: .secp160r1)
        await refresh(); return keys.eids.first?.eid.hex ?? ""
    }
    public func recoveryURL() async throws -> URL {
        let cookies = try await TokenManager.sharedInstance.getLoginCookies()
        let _: Bool = try await googleCallback(seconds: 10) { done in CookieCache.addCookies(cookies: cookies) { done(.success(true)) } }
        guard let url = SecurityDomainUrlGenerator.getUrl() else { throw googleError("Google-Schlüsselwiederherstellung konnte nicht geöffnet werden.") }
        return url
    }
    public func recoverKeys(vaultKeys: String) async throws {
        guard let data = vaultKeys.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["finder_hw"] as? [[String: Any]],
              let keyObject = entries.sorted(by: { ($0["epoch"] as? Int ?? 0) > ($1["epoch"] as? Int ?? 0) }).first?["key"] as? [String: Any] else { throw googleError("Google hat keine passenden Schlüssel geliefert.") }
        let bytes = try (0..<keyObject.count).map { index -> UInt8 in
            guard let value = keyObject[String(index)] as? Int, (0...255).contains(value) else { throw googleError("Ungültiger Google-Schlüssel.") }
            return UInt8(value)
        }
        try await installSharedKey(Data(bytes)); await refresh()
    }
    private func installSharedKey(_ shared: Data) async throws {
        let info = try await EidInfoProvider.get()
        let owner = try AESGCM.decrypt(key: shared, encryptedDataAndIV: info.encryptedOwnerKeyAndMetadata.encryptedOwnerKey)
        try KeychainStore.shared.save(shared.hex, for: .sharedKey); try KeychainStore.shared.save(owner.hex, for: .ownerKey)
        TokenManager.sharedInstance.sharedKey = shared.hex; TokenManager.sharedInstance.ownerKey = owner.hex
        TokenManager.sharedInstance.ownerKeyVersion = Int(info.encryptedOwnerKeyAndMetadata.ownerKeyVersion)
    }
    public func importSecrets(_ data: Data) async throws {
        guard firmwareDeviceID == nil else { throw googleError("Bitte zuerst die Motorola-Aktualisierung beenden.") }
        guard data.count <= 2_000_000, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["username"] as? String, email.contains("@"), let token = json["aas_token"] as? String, !token.isEmpty else { throw googleError("username und aas_token fehlen in der JSON-Datei.") }
        func key(_ name: String) throws -> String? {
            guard let value = json[name] as? String, !value.isEmpty else { return nil }
            guard value.count == 64, value.allSatisfy(\.isHexDigit) else { throw googleError("\(name) ist kein gültiger 32-Byte-Schlüssel.") }
            return value
        }
        let owner = try key("owner_key"), shared = try key("shared_key")
        try await PushReceiver.sharedInstance.prepare()
        guard let id = PushReceiver.sharedInstance.getAndroidId() else { throw googleError("Google-Registrierung fehlt.") }
        let result: [String: String] = try await googleCallback { done in
            PlayServicesOAuth.performOauth(email: email, aasToken: token, androidID: String(id), service: "oauth2:https://www.googleapis.com/auth/android_device_manager", app: "com.google.android.apps.adm", completion: done)
        }
        guard result["Auth"]?.isEmpty == false else { throw googleError("Google hat den importierten Zugang nicht bestätigt. Der bisherige Zugang bleibt erhalten.") }
        let manager = TokenManager.sharedInstance
        let previousToken = manager.aasToken, previousOwner = manager.ownerKey, previousShared = manager.sharedKey
        do { try KeychainStore.shared.save(token, for: .aasToken); try KeychainStore.shared.save(owner, for: .ownerKey); try KeychainStore.shared.save(shared, for: .sharedKey) }
        catch { try? KeychainStore.shared.save(previousToken, for: .aasToken); try? KeychainStore.shared.save(previousOwner, for: .ownerKey); try? KeychainStore.shared.save(previousShared, for: .sharedKey); throw error }
        generation = UUID(); locating.removeAll(); locationRequests.reset(); locationStatus.removeAll(); locationSucceeded.removeAll(); Settings.sharedInstance.devicesList = nil
        manager.clearCachedTokens(); manager.username = email; manager.aasToken = token; manager.ownerKey = owner; manager.sharedKey = shared
        manager.ownerKeyVersion = json["owner_key_version"] as? Int ?? 1
        publishSnapshots(); await refresh(); restartPolling()
    }
    public func signOut() {
        guard firmwareDeviceID == nil else { errorMessage = "Bitte zuerst die Motorola-Aktualisierung beenden."; return }
        generation = UUID(); polling?.cancel(); polling = nil; locating.removeAll(); locationRequests.reset(); locationStatus.removeAll(); locationSucceeded.removeAll()
        Settings.sharedInstance.devicesList = nil
        TokenManager.sharedInstance.deleteTokens(); restored = false; publishSnapshots()
    }
    #if DEBUG
    // In-memory UI fixture: no Keychain writes, no server or Google network calls.
    public func useUITestState() {
        uiTestState = true; restored = true; polling?.cancel(); polling = nil
        hasCredentials = true; account = "ui-test@example.invalid"; needsKeys = false
        trackers = [GoogleTrackerSnapshot(id: "demo-local-tag", name: "Lokaler Test-Tracker", imageURL: "",
            latitude: 52.5163, longitude: 13.3777, accuracy: 10, reportedAt: .now, nearby: false,
            battery: nil, reportCount: 0, historyEnabled: true, unlocked: true, isLost: false, sharedWith: [], signal: nil)]
    }
    #endif

}

