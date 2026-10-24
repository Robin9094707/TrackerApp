import XCTest
import CryptoKit
@testable import SpotIntegration

final class MotorolaOwnerProofTests: XCTestCase {
    private let nonce = Data(1...9)
    private let key = Data(repeating: 0x37, count: 16)
    private func packet(flags: UInt8 = 3, eidLength: Int = 20) -> Data {
        let payload = Data([flags]) + Data(repeating: 0x48, count: eidLength)
        let header = Data([1, UInt8(8 + payload.count)])
        let mac = Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: nonce + header + payload + Data([1]), using: SymmetricKey(data: key)).prefix(8))
        return header + mac + payload
    }
    func testReadOnlyProofAcceptsOnlyAuthenticatedProvisionedOwner() throws {
        XCTAssertEqual(try MotorolaOwnerProof.request(authentication: nonce, key: key).prefix(2), Data([1, 8]))
        try MotorolaOwnerProof.verify(packet(), authentication: nonce, key: key)
        try MotorolaOwnerProof.verify(packet(eidLength: 32), authentication: nonce, key: key)
        for flags: UInt8 in [0, 1, 2] {
            XCTAssertThrowsError(try MotorolaOwnerProof.verify(packet(flags: flags), authentication: nonce, key: key))
        }
    }
    func testTamperingStaleNonceWrongKeyAndTruncationAreRejected() {
        var changed = packet(); changed[12] ^= 1
        for invalid in [Data(), packet().dropLast(), changed, packet(eidLength: 19)] {
            XCTAssertThrowsError(try MotorolaOwnerProof.verify(invalid, authentication: nonce, key: key))
        }
        XCTAssertThrowsError(try MotorolaOwnerProof.verify(packet(), authentication: Data(repeating: 1, count: 9), key: key))
        XCTAssertThrowsError(try MotorolaOwnerProof.verify(packet(), authentication: nonce, key: Data(repeating: 0, count: 16)))
        XCTAssertThrowsError(try MotorolaOwnerProof.request(authentication: Data(), key: key))
    }
    func testOnlyKnownMotorolaIdentifiersAreRecognized() {
        XCTAssertEqual(MotorolaTagModel.identify("B4122F"), .firstGeneration)
        XCTAssertEqual(MotorolaTagModel.identify("3390ea"), .firstGeneration)
        XCTAssertEqual(MotorolaTagModel.identify("XT2561-1"), .secondGeneration)
        for unknown in ["moto tag", "Motorola", "ESP32", "", "b4122f-unknown"] {
            XCTAssertNil(MotorolaTagModel.identify(unknown))
        }
    }
}
