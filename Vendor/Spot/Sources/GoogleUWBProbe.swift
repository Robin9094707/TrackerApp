import Foundation
import CryptoKit

public struct GoogleUWBCapabilities: Equatable {
    public let supportsUWB: Bool
    public let channels: [Int]
    public let configIDs: [Int]
    public let minimumIntervalMS: Int?
    public let supportsInitiator: Bool
}

// FHNA operation 0x0A only. Never sends ranging configuration (0x0B),
// pairing/reset commands, or a session key. Capabilities are not ranging data.
// https://developers.google.com/nearby/fast-pair/specifications/extensions/fmdn
// https://source.android.com/docs/core/connect/ranging-oob-spec
// V1 is requested deliberately; newer responders must negotiate down to v1.
enum GoogleUWBProbe {
    static let capabilityRequest = Data([0x01, 0x00, 0x01, 0x00])

    static func request(authentication: Data, accountKey: Data) throws -> Data {
        let auth = try validatedAuthentication(authentication, accountKey: accountKey)
        let header = Data([0x0A, UInt8(8 + capabilityRequest.count)])
        let mac = authenticate(Data([auth[0]]) + Data(auth[1..<9]) + header + capabilityRequest, key: accountKey)
        return header + mac + capabilityRequest
    }

    static func response(_ packet: Data, authentication: Data, accountKey: Data) throws -> GoogleUWBCapabilities {
        let auth = try validatedAuthentication(authentication, accountKey: accountKey)
        let bytes = Array(packet)
        guard bytes.count >= 14, bytes[0] == 0x0A, Int(bytes[1]) == bytes.count - 2 else {
            throw googleError("Keine vollständige UWB-Fähigkeitsantwort. Die Firmware unterstützt diese Abfrage möglicherweise nicht.")
        }
        let payload = Data(bytes.dropFirst(10))
        let expected = authenticate(Data([auth[0]]) + Data(auth[1..<9]) + Data(bytes.prefix(2)) + payload + Data([0x01]), key: accountKey)
        let difference = zip(expected, bytes[2..<10]).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else { throw googleError("Die UWB-Antwort konnte nicht authentifiziert werden.") }
        return try parseCapabilities(payload)
    }

    static func parseCapabilities(_ payload: Data) throws -> GoogleUWBCapabilities {
        let bytes = Array(payload)
        guard bytes.count >= 4, bytes[0] == 1, bytes[1] == 1 else {
            throw googleError("Unbekannte Version der UWB-Fähigkeitsantwort.")
        }
        let supportsUWB = bytes[2] & 1 != 0
        var offset = 4
        var uwb: GoogleUWBCapabilities?
        while offset < bytes.count {
            guard offset + 2 <= bytes.count else { throw googleError("Abgeschnittene UWB-Fähigkeitsdaten.") }
            let technology = bytes[offset], size = Int(bytes[offset + 1])
            guard size >= 2, offset + size <= bytes.count else { throw googleError("Ungültige Länge der UWB-Fähigkeitsdaten.") }
            if technology == 0 {
                guard supportsUWB, size >= 20, uwb == nil else { throw googleError("Widersprüchliche UWB-Fähigkeitsdaten.") }
                func uint(_ relative: Int, count: Int) -> UInt32 {
                    (0..<count).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + relative + $1]) << ($1 * 8) }
                }
                let channels = uint(4, count: 4), configs = uint(12, count: 4)
                uwb = GoogleUWBCapabilities(supportsUWB: true,
                    channels: (0..<32).filter { channels & (UInt32(1) << $0) != 0 },
                    configIDs: (0..<32).filter { configs & (UInt32(1) << $0) != 0 },
                    minimumIntervalMS: Int(uint(16, count: 2)), supportsInitiator: bytes[offset + 19] & 1 != 0)
            }
            offset += size
        }
        if let uwb { return uwb }
        guard !supportsUWB else { throw googleError("UWB wurde angekündigt, aber ohne zugehörige Fähigkeitsdaten.") }
        return GoogleUWBCapabilities(supportsUWB: false, channels: [], configIDs: [], minimumIntervalMS: nil, supportsInitiator: false)
    }

    private static func validatedAuthentication(_ authentication: Data, accountKey: Data) throws -> [UInt8] {
        guard authentication.count == 9, accountKey.count == 16 else { throw googleError("Google-Accountschlüssel oder Bluetooth-Nonce ist ungültig.") }
        return Array(authentication)
    }
    private static func authenticate(_ data: Data, key: Data) -> Data {
        Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)).prefix(8))
    }
}
