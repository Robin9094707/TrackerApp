import Foundation
import CryptoKit

/// Only catalogue identifiers recovered from Motorola's own model dispatch table.
public enum MotorolaTagModel: String, CaseIterable {
    case firstGeneration = "XT2445-1"
    case secondGeneration = "XT2561-1"

    public static func identify(_ identifier: String) -> Self? {
        switch identifier.lowercased() {
        case "xt2445-1", "3390ea", "b4122f": return .firstGeneration
        case "xt2561-1", "8c9712", "97b899": return .secondGeneration
        default: return nil
        }
    }
}

public struct MotorolaFirmwareTarget {
    public let deviceID: String
    public let peripheralID: UUID
    public let model: MotorolaTagModel
    public let fastPairModelID: String
    let generation: UUID
}

// Read provisioning state (0x01) proves that the selected peripheral accepts this
// account's OWNER key and is provisioned. No pairing, reset or key writes.
enum MotorolaOwnerProof {
    static func request(authentication: Data, key: Data) throws -> Data {
        try validate(authentication, key)
        let header = Data([0x01, 0x08])
        return header + mac(authentication + header, key)
    }

    static func verify(_ packet: Data, authentication: Data, key: Data) throws {
        try validate(authentication, key)
        let bytes = Array(packet)
        guard [31, 43].contains(bytes.count), bytes[0] == 1,
              Int(bytes[1]) == bytes.count - 2 else { throw googleError("Ungültige Eigentümerantwort des Moto Tag.") }
        let payload = Data(bytes.dropFirst(10))
        let expected = mac(authentication + Data(bytes.prefix(2)) + payload + Data([1]), key)
        guard zip(expected, bytes[2..<10]).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0,
              bytes[10] & 3 == 3 else { throw googleError("Firmwareupdates benötigen den bestätigten Eigentümerschlüssel dieses Tags.") }
    }

    private static func validate(_ authentication: Data, _ key: Data) throws {
        guard authentication.count == 9, key.count == 16 else { throw googleError("Google-Schlüssel oder Bluetooth-Authentifizierung ist ungültig.") }
    }
    private static func mac(_ data: Data, _ key: Data) -> Data {
        Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)).prefix(8))
    }
}
