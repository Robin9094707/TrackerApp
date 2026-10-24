import Foundation

// Keep the original encrypted report messages, including reports whose keys are not yet
// unlocked. Replaying them after key recovery does not depend on another network fetch.
enum GoogleReportArchive {
    static func directory() throws -> URL {
        let account = TokenManager.sharedInstance.username?.lowercased() ?? "unconfigured"
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoogleProtocol", isDirectory: true)
            .appendingPathComponent(SHA256.hash(data: Data(account.utf8)).hex, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func storeCatalog(_ list: DevicesList) throws {
        let url = try directory().appendingPathComponent("devices.pb")
        try list.serializedData().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func catalog() -> DevicesList? {
        guard let url = try? directory().appendingPathComponent("devices.pb"), let data = try? Data(contentsOf: url) else { return nil }
        return try? DevicesList(serializedBytes: data)
    }
    static func store(_ update: DeviceUpdate) {
        do {
            var canonical = update
            canonical.clearFcmMetadata()
            let data = try canonical.serializedData()
            let url = try directory().appendingPathComponent(SHA256.hash(data: data).hex + ".report")
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { showAlert(title: "Google-Verlauf", message: "Eine Google-Meldung konnte nicht lokal gesichert werden.") }
    }
    static func replay(devices: [LocalFindMyDevice]) {
        guard let folder = try? directory(), let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "report" {
            guard let data = try? Data(contentsOf: url), let update = try? DeviceUpdate(serializedBytes: data) else { continue }
            let id = getInformation(deviceMetadata: update.deviceMetadata).deviceRegistration.canonicID.id
            if let device = devices.first(where: { $0.id == id }) {
                _ = mergeDeviceUpdate(requestDate: Date(), contributorType: .AtAllAreas, deviceUpdateProtobuf: update, localDevice: device)
            }
        }
    }
}

func uniqueGoogleReports(_ reports: [LocationReportWrapper]) -> [LocationReportWrapper] {
    var seen = Set<String>()
    return reports.filter { report in
        let location = report.decryptedLocation.map { "\($0.latitude):\($0.longitude):\($0.altitude)" }
            ?? (report.encryptedLocation.flatMap { try? $0.serializedData() }?.base64EncodedString() ?? report.name ?? "")
        let key = "\(report.time.timeIntervalSince1970)|\(report.status.rawValue)|\(report.isOwnReport)|\(location)"
        return seen.insert(key).inserted
    }.sorted { $0.time > $1.time }
}
