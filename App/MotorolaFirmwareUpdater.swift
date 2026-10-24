import Foundation
import Combine
import UIKit
import SpotIntegration
import iOSMcuManagerLibrary

@MainActor
final class MotorolaFirmwareUpdater: NSObject, ObservableObject, FirmwareUpgradeDelegate {
    static let shared = MotorolaFirmwareUpdater()
    @Published private(set) var package: MotorolaFirmwarePackage?
    @Published private(set) var info: MotorolaHardwareInfo?
    @Published private(set) var inspectedDeviceID: String?
    @Published private(set) var busy = false
    @Published private(set) var updating = false
    @Published private(set) var canCancel = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = "Originalfirmware importieren und eigenen Moto Tag prüfen."
    @Published private(set) var errorMessage: String?
    private var manager: FirmwareUpgradeManager?
    private var transport: McuMgrBleTransport?
    private var access: MotorolaFirmwareTarget?
    private var inspector: MotorolaBLEInspector?
    private var previousIdleTimer = false
    private var idleTimerChanged = false
    private let google = GoogleTrackerStore.shared

    override private init() {
        super.init()
        if let url = try? Self.cacheURL(), let data = try? Data(contentsOf: url), let original = try? MotorolaFirmwarePackage.validate(data) {
            package = original
        }
    }
    private static func cacheURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MotorolaFirmware", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("XT2445-1-2.0.104.bin")
    }
    func importFile(_ url: URL) async {
        guard !busy else { return }
        busy = true; errorMessage = nil
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() }; busy = false }
        do {
            let original = try await Task.detached(priority: .userInitiated) { try MotorolaFirmwarePackage.load(from: url) }.value
            try original.data.write(to: Self.cacheURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            package = original; status = "Motorola-Original 2.0.104 geprüft und bereit."
        } catch { errorMessage = error.localizedDescription }
    }
    func inspect(_ deviceID: String) async {
        guard !busy else { return }
        busy = true; info = nil; inspectedDeviceID = nil; errorMessage = nil
        status = "Eigentümer, Modell und Firmware prüfen …"
        defer { busy = false }
        do {
            let lease = try await google.beginMotorolaFirmwareAccess(deviceID)
            defer { google.endMotorolaFirmwareAccess(lease) }
            let reader = MotorolaBLEInspector(); inspector = reader
            defer { inspector = nil }
            let current = try await reader.read(lease)
            guard google.motorolaAccessIsCurrent(lease) else { throw CancellationError() }
            info = current; inspectedDeviceID = deviceID
            status = "Gerätedaten direkt vom Moto Tag gelesen."
        } catch { status = "Prüfung nicht abgeschlossen."; errorMessage = error.localizedDescription }
    }
    func canInstall(_ deviceID: String) -> Bool {
        guard !busy, inspectedDeviceID == deviceID, let info, let package,
              google.motorolaModel(deviceID) == .firstGeneration else { return false }
        return (try? MotorolaFirmwarePolicy.validate(info: info, expectedModelID: info.modelID, package: package)) != nil
    }
    func install(_ deviceID: String) async {
        guard canInstall(deviceID), let original = package else { return }
        busy = true; updating = true; errorMessage = nil; progress = 0; canCancel = false
        status = "Eigentümer und Batterie erneut prüfen …"
        do {
            let lease = try await google.beginMotorolaFirmwareAccess(deviceID)
            access = lease
            let reader = MotorolaBLEInspector(); inspector = reader
            let current = try await reader.read(lease)
            inspector = nil
            guard google.motorolaAccessIsCurrent(lease) else { throw CancellationError() }
            try MotorolaFirmwarePolicy.validate(info: current, expectedModelID: lease.fastPairModelID, package: original)
            let verified = try MotorolaFirmwarePackage.validate(original.data)
            let image = try McuMgrImage(data: verified.data)
            // Motorola's original app uses CONFIRM_ONLY, a 10-second swap delay,
            // and no app-settings erase. Use conservative non-pipelined transfer.
            let link = McuMgrBleTransport(lease.peripheralID)
            transport = link
            let update = FirmwareUpgradeManager(transport: link, delegate: self)
            manager = update
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true; idleTimerChanged = true
            update.start(images: [ImageManager.Image(image: 0, hash: image.hash, data: verified.data)],
                using: FirmwareUpgradeConfiguration(estimatedSwapTime: 10, eraseAppSettings: false,
                    pipelineDepth: 1, upgradeMode: .confirmOnly))
        } catch { fail(error) }
    }
    func cancelUpload() {
        guard canCancel else { return }
        canCancel = false; status = "Upload wird abgebrochen …"; manager?.cancel()
    }
    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription; status = "Update nicht bestätigt. Gerät erneut prüfen."
        info = nil; inspectedDeviceID = nil; cleanup()
    }
    private func cleanup() {
        transport?.close(); transport = nil; manager = nil; inspector = nil
        if let access { google.endMotorolaFirmwareAccess(access) }; access = nil
        if idleTimerChanged { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer; idleTimerChanged = false }
        busy = false; updating = false; canCancel = false
    }
    private func verifyAfterRestart() async {
        guard let lease = access, let expected = package else { return }
        canCancel = false; status = "Neustart abgeschlossen – installierte Version prüfen …"
        transport?.close(); transport = nil; manager = nil
        do {
            try await Task.sleep(for: .seconds(3))
            guard google.motorolaAccessIsCurrent(lease) else { throw CancellationError() }
            let reader = MotorolaBLEInspector(); inspector = reader
            let installed = try await reader.read(lease)
            guard installed.firmware == expected.version, installed.modelID == lease.fastPairModelID else {
                throw MotorolaFirmwareError.invalid("Die erwartete Firmware 2.0.104 wurde nach dem Neustart nicht bestätigt.")
            }
            info = installed; inspectedDeviceID = lease.deviceID; progress = 1
            status = "Firmware 2.0.104 nach dem Neustart vom Tag bestätigt."
            cleanup()
        } catch { fail(error) }
    }
    nonisolated func upgradeDidStart(controller: FirmwareUpgradeController) {
        Task { @MainActor [weak self] in self?.status = "Motorola-Original wird über Bluetooth übertragen …" }
    }
    nonisolated func upgradeStateDidChange(from previousState: FirmwareUpgradeState, to newState: FirmwareUpgradeState) {
        Task { @MainActor [weak self] in
            guard let self, self.updating else { return }
            self.canCancel = newState == .upload
            if newState == .reset { self.status = "Firmware aktivieren und Tag neu starten …" }
            else if newState == .confirm { self.status = "Firmware vom Tag bestätigen lassen …" }
        }
    }
    nonisolated func upgradeDidComplete() { Task { @MainActor [weak self] in await self?.verifyAfterRestart() } }
    nonisolated func upgradeDidFail(inState state: FirmwareUpgradeState, with error: Error) {
        Task { @MainActor [weak self] in self?.fail(error) }
    }
    nonisolated func upgradeDidCancel(state: FirmwareUpgradeState) {
        Task { @MainActor [weak self] in
            self?.status = "Upload abgebrochen. Vor einem neuen Versuch Gerät erneut prüfen."
            self?.info = nil; self?.inspectedDeviceID = nil; self?.cleanup()
        }
    }
    nonisolated func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        Task { @MainActor [weak self] in
            guard imageSize > 0, self?.updating == true else { return }
            self?.progress = min(1, max(0, Double(bytesSent) / Double(imageSize)))
        }
    }
}
