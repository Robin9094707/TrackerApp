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

// One identity for both deduplication and SwiftUI rows. Include altitude and
// semantic labels so distinct reports never share a row or disappear on replay.
func googleReportIdentity(_ report: LocationReportWrapper) -> String {
    let location = report.decryptedLocation
    let payload = location == nil ? report.encryptedLocation.flatMap { try? $0.serializedData() }?.base64EncodedString() : nil
    let fields: [String?] = [String(report.time.timeIntervalSince1970), String(report.status.rawValue),
        String(report.isOwnReport), report.accuracy.map { String($0) },
        location.map { String($0.latitude) }, location.map { String($0.longitude) },
        location.map { String($0.altitude) }, report.name, payload]
    // Length prefixes keep names containing separators unambiguous.
    let canonical = fields.map { field in field.map { "\($0.utf8.count):\($0)" } ?? "-" }.joined(separator: "|")
    return SHA256.hash(data: Data(canonical.utf8)).hex
}

func uniqueGoogleReports(_ reports: [LocationReportWrapper]) -> [LocationReportWrapper] {
    var seen = Set<String>()
    return reports.filter { seen.insert(googleReportIdentity($0)).inserted }
        .sorted { $0.time > $1.time }
}
