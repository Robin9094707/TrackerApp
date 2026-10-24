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
    private var lastCatalog = Date.distantPast
    private var lastMaintenance = Date.distantPast
    nonisolated public static func validInterval(_ value: Int) -> Int { [0, 60, 120, 300, 900].contains(value) ? value : 60 }

    private init() {
        refreshInterval = Self.validInterval(preferences.object(forKey: "native.refreshInterval") as? Int ?? 60)
        contributorMode = preferences.string(forKey: "native.contributorMode") ?? "AtAllAreas"
        Settings.sharedInstance.contributorType = ContributorType(rawValue: contributorMode) ?? .AtAllAreas
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
        publishSnapshots() // v5.0's onboarding flag is deliberately ignored. Valid tokens go straight into the native app.
    }
    public func clearError() { errorMessage = nil }
    public func hasDevice(_ id: String) -> Bool { trackers.contains { $0.id == id } }
    public func favoriteOverride(_ id: String) -> Bool? { preferences.object(forKey: favoriteKey(id)) as? Bool }
    public func favorite(_ id: String) -> Bool { preferences.bool(forKey: favoriteKey(id)) }
    public func setFavorite(_ id: String, enabled: Bool) { preferences.set(enabled, forKey: favoriteKey(id)); objectWillChange.send() }
    private func favoriteKey(_ id: String) -> String { "native.favorite." + SHA256.hash(data: Data(((account ?? "") + id).utf8)).hex }
    private func device(_ id: String) throws -> LocalFindMyDevice {
        guard let device = Settings.sharedInstance.devicesList?.first(where: { $0.id == id }), device.belongsToCurrentAccount else { throw googleError("Google-Tracker ist noch nicht geladen.") }
        return device
    }
    public func reports(for id: String) -> [GoogleReportSnapshot] {
        guard let device = try? device(id) else { return [] }
        return uniqueGoogleReports(device.refreshes.flatMap(\.reports)).map { report in
            let location = report.decryptedLocation
            let encrypted = location == nil ? (report.encryptedLocation.flatMap { try? $0.serializedData() }?.base64EncodedString() ?? "") : ""
            let fingerprint = "\(report.time.timeIntervalSince1970)|\(report.status.rawValue)|\(location?.latitude ?? 0)|\(location?.longitude ?? 0)|\(report.isOwnReport)|\(report.accuracy ?? 0)|\(report.name ?? "")|\(encrypted)"
            return GoogleReportSnapshot(id: SHA256.hash(data: Data(fingerprint.utf8)).hex, date: report.time,
                latitude: location?.latitude, longitude: location?.longitude, accuracy: report.accuracy.map(Double.init),
                kind: String(describing: report.status), own: report.isOwnReport, label: report.name)
        }
    }
    private func publishSnapshots() {
        account = TokenManager.sharedInstance.username
        hasCredentials = TokenManager.sharedInstance.aasToken != nil
        needsKeys = hasCredentials && TokenManager.sharedInstance.ownerKey == nil
        guard hasCredentials else { trackers = []; return }
        let snapshots = (Settings.sharedInstance.devicesList ?? []).filter(\.belongsToCurrentAccount).map { device in
            let reports = uniqueGoogleReports(device.refreshes.flatMap(\.reports))
            let report = reports.first { $0.decryptedLocation != nil }
            let location = report?.decryptedLocation
            let nearby = device.bluetoothData.map { !deviceNotCurrentlyReachable(device: $0, currentDate: Date()) } ?? false
            return GoogleTrackerSnapshot(id: device.id, name: device.userDefinedName, imageURL: device.imageURL,
                latitude: location?.latitude, longitude: location?.longitude, accuracy: report?.accuracy.map(Double.init),
                reportedAt: report?.time, nearby: nearby, battery: device.batteryState == .Unknown ? nil : device.batteryState.rawValue,
                reportCount: reports.count, unlocked: device.eik != nil, isLost: device.isLost,
                sharedWith: device.sharingSettings.usersWithAccess, signal: nearby ? device.bluetoothData?.rssi_publisher : nil)
        }
        if snapshots != trackers { trackers = snapshots }
    }
    public func restoreIfNeeded() async {
        guard !restored else { return }; restored = true
        if hasCredentials {
            if let cached = GoogleReportArchive.catalog() { await processDeviceList(list: cached.deviceMetadata) }
            await refresh()
        } else {
            // Recover a completed Google web login whose final token exchange was interrupted.
            let cookies: [HTTPCookie] = (try? await googleCallback(seconds: 5) { done in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { done(.success($0)) }
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
        statusMessage = "Google-Verbindung vorbereiten …"
        defer { statusMessage = nil }
        try await PushReceiver.sharedInstance.prepare()
        return URL(string: "https://accounts.google.com/EmbeddedSetup")!
    }
    public func finishLogin(oauthToken: String) async throws {
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
            Settings.sharedInstance.devicesList = nil; generation = UUID(); locating.removeAll()
        }
        manager.clearCachedTokens(); manager.username = email; manager.aasToken = token
        publishSnapshots()
        Task { await self.refresh(); self.restartPolling() }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where Self.isOAuthCookie(cookie) && cookie.value == oauthToken {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
            }
        }
    }
    public func refresh() async {
        guard !isRefreshing, hasCredentials else { return }
        isRefreshing = true; errorMessage = nil
        let generation = self.generation
        defer { isRefreshing = false }
        do {
            try await PushReceiver.sharedInstance.prepare()
            let list = try await NovaApiManager.sharedInstance.requestDeviceList()
            guard generation == self.generation else { return }
            try GoogleReportArchive.storeCatalog(list)
            if TokenManager.sharedInstance.ownerKey == nil, let shared = TokenManager.sharedInstance.sharedKey?.dataFromHex {
                try? await installSharedKey(shared)
            }
            await processDeviceList(list: list.deviceMetadata)
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
            requestReportsForAll()
        } catch { if generation == self.generation { errorMessage = error.localizedDescription } }
    }
    public func locate(_ id: String) throws {
        let device = try device(id)
        guard !locating.contains(id) else { return }
        locating.insert(id)
        let generation = self.generation
        NovaApiManager.sharedInstance.requestLocationDataForDevice(device: device) { [weak self] success in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.publishSnapshots()
                if success { self.statusMessage = "Weitere Google-Meldung für \(device.userDefinedName) empfangen." }
                else { self.statusMessage = "Empfangsfenster beendet. Bereits empfangene Reports bleiben erhalten." }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 38_000_000_000)
            guard let self, generation == self.generation else { return }
            self.locating.remove(id)
            self.publishSnapshots()
        }
    }
    public func requestReportsForAll() {
        for tracker in trackers { try? locate(tracker.id) }
    }
    public func sceneChanged(active: Bool) {
        self.active = active
        if hasCredentials { Settings.sharedInstance.isBackground = !active }
        restartPolling()
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
    public func beginNearby(_ id: String) {
        BluetoothManager.sharedInstance.startCentralManager()
        let identifier = try? device(id).bluetoothData?.identifier_background
        let uuids: [UUID] = identifier.flatMap { $0 }.flatMap { UUID(uuidString: $0) }.map { [$0] } ?? []
        BluetoothManager.sharedInstance.enableFastScan(for: RSSIScan(service: Constants.FindMyDeviceService), allowedUUIDs: uuids)
    }
    public func endNearby() { BluetoothManager.sharedInstance.disableFastScan() }
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
        generation = UUID(); locating.removeAll(); Settings.sharedInstance.devicesList = nil
        manager.clearCachedTokens(); manager.username = email; manager.aasToken = token; manager.ownerKey = owner; manager.sharedKey = shared
        manager.ownerKeyVersion = json["owner_key_version"] as? Int ?? 1
        publishSnapshots(); await refresh(); restartPolling()
    }
    public func signOut() {
        generation = UUID(); polling?.cancel(); polling = nil; locating.removeAll()
        Settings.sharedInstance.devicesList = nil
        TokenManager.sharedInstance.deleteTokens(); restored = false; publishSnapshots()
    }
}
