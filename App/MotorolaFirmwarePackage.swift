import Foundation
import CryptoKit
import ZIPFoundation
import SpotIntegration

enum MotorolaFirmwareError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct MotorolaFirmwarePackage {
    let model: MotorolaTagModel
    let version: String
    let data: Data
    let sha256: String
    static let maximumArchiveSize = 64 * 1024 * 1024
    // Exact original image from com.motorola.tag 01.01.101.23-Release.
    // This allowlist verifies bytes, not merely the APK filename or manifest.
    static let originalSHA256 = "e1fd8c3eb5be56010bfa6fbddcca3cf3df8418f336e1ce3a7d759271b72baa1e"
    static let originalImageSize = 508_762
    static let assetPath = "assets/nano_v2.0.104/OTA.bin"

    static func validate(_ data: Data) throws -> Self {
        guard data.count == originalImageSize,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == originalSHA256 else {
            throw MotorolaFirmwareError.invalid("Keine freigegebene Motorola-Originalfirmware für XT2445-1. Aktuell wird nur das geprüfte Original 2.0.104 akzeptiert.")
        }
        return Self(model: .firstGeneration, version: "2.0.104", data: data, sha256: originalSHA256)
    }

    static func load(from url: URL) throws -> Self {
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result {
                let values = try readableURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw MotorolaFirmwareError.invalid("Bitte eine einzelne APK-, APKM- oder BIN-Datei auswählen.") }
                let size = values.fileSize ?? 0
                guard size > 0, size <= maximumArchiveSize else { throw MotorolaFirmwareError.invalid("Originaldatei fehlt oder überschreitet 64 MB.") }
                return try decode(Data(contentsOf: readableURL, options: .mappedIfSafe))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw MotorolaFirmwareError.invalid("Die Datei konnte nicht geladen werden. Bitte zuerst in Dateien vollständig herunterladen und erneut auswählen.") }
        return try result.get()
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumArchiveSize else { throw MotorolaFirmwareError.invalid("Die Datei ist zu groß.") }
        if data.count == originalImageSize { return try validate(data) }
        let archive: Archive
        do { archive = try Archive(data: data, accessMode: .read) }
        catch { throw MotorolaFirmwareError.invalid("Bitte Motorola-Original als APK, APKM oder OTA.bin wählen.") }
        if let entry = archive[assetPath] {
            return try validate(extract(entry, from: archive, limit: originalImageSize))
        }
        if let base = archive["base.apk"] {
            let apk = try extract(base, from: archive, limit: maximumArchiveSize)
            let inner = try Archive(data: apk, accessMode: .read)
            guard let entry = inner[assetPath] else { throw MotorolaFirmwareError.invalid("Dieses APKM enthält keine freigegebene Moto-Tag-Firmware 2.0.104.") }
            return try validate(extract(entry, from: inner, limit: originalImageSize))
        }
        throw MotorolaFirmwareError.invalid("Keine passende Motorola-Firmware enthalten. Google Find Hub und Uptodown enthalten dieses Update nicht.")
    }
    private static func extract(_ entry: Entry, from archive: Archive, limit: Int) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= UInt64(limit) else { throw MotorolaFirmwareError.invalid("Ungültige oder übergroße Firmware im Archiv.") }
        var bytes = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard chunk.count <= limit - bytes.count else { throw MotorolaFirmwareError.invalid("Das Archiv überschreitet die erlaubte Größe.") }
            bytes.append(chunk)
        }
        guard checksum == entry.checksum else { throw MotorolaFirmwareError.invalid("Archiv-Prüfsumme stimmt nicht.") }
        return bytes
    }
}

struct MotorolaHardwareInfo: Equatable {
    let modelID: String
    let firmware: String
    let hardware: String
    let battery: Int
}

enum MotorolaFirmwarePolicy {
    static func validate(info: MotorolaHardwareInfo, expectedModelID: String, package: MotorolaFirmwarePackage) throws {
        guard package.model == .firstGeneration,
              MotorolaTagModel.identify(info.modelID) == .firstGeneration,
              info.modelID == expectedModelID.lowercased() else { throw MotorolaFirmwareError.invalid("Die vom Tag gemeldete Modellkennung passt nicht zur Originalfirmware.") }
        guard info.battery >= 30, info.battery <= 100 else { throw MotorolaFirmwareError.invalid("Die Tag-Batterie muss mindestens 30 % haben.") }
        guard let current = version(info.firmware), let next = version(package.version), current.lexicographicallyPrecedes(next) else {
            throw MotorolaFirmwareError.invalid("Das Original 2.0.104 ist nicht neuer als die gemeldete Firmware. Ein Downgrade wird nicht gestartet.")
        }
    }
    static func version(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ (0...255).contains($0) }), numbers != [0, 0, 0] else { return nil }
        return numbers
    }
}

// Motorola vendor PDU: feature, subfeature, flags, big-endian payload length.
// Only the three read commands observed in the original APK are exposed.
enum MotorolaReadProtocol {
    static let service = "018EFC7C-6B58-79D2-BC8F-0BE0388883BB"
    static let command = "FC7C08A0-6B58-79D2-BC8F-0BE0388883BB"
    static let response = "FC7C08A1-6B58-79D2-BC8F-0BE0388883BB"
    static func request(_ subfeature: UInt8) throws -> Data {
        guard [4, 5, 6].contains(subfeature) else { throw MotorolaFirmwareError.invalid("Unzulässiger Motorola-Lesebefehl.") }
        return Data([0, subfeature, 0x80, 0, 0])
    }
    static func payload(_ packet: Data, expected: UInt8) throws -> Data {
        let b = Array(packet)
        guard b.count >= 5, b[0] == 0, b[1] == expected,
              b[2] & 0x60 == 0x20, b[2] & 0x1F == 0,
              Int(b[3]) * 256 + Int(b[4]) == b.count - 5 else { throw MotorolaFirmwareError.invalid("Ungültige oder nicht unterstützte Motorola-Antwort.") }
        return Data(b.dropFirst(5))
    }
    static func model(_ payload: Data) throws -> String {
        guard payload.count == 4 else { throw MotorolaFirmwareError.invalid("Modellantwort ist unvollständig.") }
        return payload.prefix(3).map { String(format: "%02x", $0) }.joined()
    }
    static func hardware(_ payload: Data) throws -> (firmware: String, hardware: String) {
        let b = Array(payload)
        guard b.count == 24 else { throw MotorolaFirmwareError.invalid("Firmware-/Hardwareantwort ist unvollständig.") }
        return (b[19..<22].map(String.init).joined(separator: "."), b[22..<24].map { String(format: "%02x", $0) }.joined())
    }
    static func battery(_ payload: Data) throws -> Int {
        guard (1...2).contains(payload.count), let byte = payload.first, byte & 0x7F <= 100 else { throw MotorolaFirmwareError.invalid("Batteriestand konnte nicht sicher gelesen werden.") }
        return Int(byte & 0x7F)
    }
}
