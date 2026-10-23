// RJ Tracker integration of Spot (Leon Böttger), GPL-3.0-only.
import SwiftUI
import Combine
import CoreBluetooth
import LUI

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
}

@MainActor
public final class GoogleTrackerStore: ObservableObject {
    public static let shared = GoogleTrackerStore()
    @Published public private(set) var trackers: [GoogleTrackerSnapshot] = []
    @Published public private(set) var account: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?
    private var subscriptions = Set<AnyCancellable>()
    private var deviceSubscriptions = Set<AnyCancellable>()
    private var restored = false

    private init() {
        LUIInit(configuration: configuration)
        Settings.sharedInstance.$devicesList.receive(on: DispatchQueue.main).sink { [weak self] devices in
            guard let self else { return }
            self.deviceSubscriptions.removeAll()
            for device in devices ?? [] {
                device.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
                    // objectWillChange is sent before the new report is assigned.
                    DispatchQueue.main.async { self?.publishSnapshots() }
                }.store(in: &self.deviceSubscriptions)
            }
            DispatchQueue.main.async { self.publishSnapshots() }
        }.store(in: &subscriptions)
        TokenManager.sharedInstance.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.publishSnapshots() }
        }.store(in: &subscriptions)
        publishSnapshots()
    }

    private func publishSnapshots() {
        account = TokenManager.sharedInstance.username
        guard TokenManager.sharedInstance.aasToken != nil else { trackers = []; return }
        trackers = (Settings.sharedInstance.devicesList ?? []).map { device in
            let report = device.refreshes.flatMap(\.reports)
                .filter { $0.decryptedLocation != nil }.max { $0.time < $1.time }
            let location = report?.decryptedLocation
            let nearby = device.bluetoothData.map {
                !deviceNotCurrentlyReachable(device: $0, currentDate: Date())
            } ?? false
            return GoogleTrackerSnapshot(id: device.id, name: device.userDefinedName, imageURL: device.imageURL,
                latitude: location?.latitude, longitude: location?.longitude,
                accuracy: report?.accuracy.map(Double.init), reportedAt: report?.time,
                nearby: nearby, battery: device.batteryState == .Unknown ? nil : device.batteryState.rawValue)
        }
    }

    public func restoreIfNeeded() async {
        guard !restored, TokenManager.sharedInstance.aasToken != nil else { return }
        restored = true
        await refresh()
    }

    public func refresh() async {
        guard !isRefreshing, TokenManager.sharedInstance.aasToken != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await prepareGoogleConnection()
            let account = TokenManager.sharedInstance.username?.lowercased()
            let response = try await NovaApiManager.sharedInstance.requestDeviceList()
            guard account == TokenManager.sharedInstance.username?.lowercased() else { return }
            await processDeviceList(list: response.deviceMetadata)
            errorMessage = nil
            if CBManager.authorization == .allowedAlways { BluetoothManager.sharedInstance.startCentralManager() }
        } catch { errorMessage = error.localizedDescription }
    }

    public func sceneChanged(active: Bool) {
        guard TokenManager.sharedInstance.aasToken != nil else { return }
        Settings.sharedInstance.isBackground = !active
    }
}

func prepareGoogleConnection() async throws {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        PushReceiver.sharedInstance.registerForLogin { continuation.resume() }
    }
    guard PushReceiver.sharedInstance.getToken() != nil, PushReceiver.sharedInstance.getAndroidId() != nil else {
        throw NSError(domain: "SpotGoogle", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Google-Verbindung konnte nicht vorbereitet werden. Bitte Internetverbindung prüfen und erneut versuchen."])
    }
}

public struct GoogleTrackerExperience: View {
    private let initialDeviceID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    public init(initialDeviceID: String? = nil) {
        self.initialDeviceID = initialDeviceID
        _ = GoogleTrackerStore.shared
    }
    public var body: some View {
        ContentView(initialDeviceID: initialDeviceID)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Label("Google · auf diesem iPhone", systemImage: "lock.iphone").font(.caption.weight(.medium))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .accessibilityLabel("Zurück zu RJ Tracker")
                }
                .padding(.horizontal, 18).padding(.vertical, 10).background(.regularMaterial)
            }
            .onChange(of: phase) { _, phase in GoogleTrackerStore.shared.sceneChanged(active: phase == .active) }
    }
}
