import XCTest
@testable import SpotIntegration

final class GoogleKeyPreservationTests: XCTestCase {
    private func metadata(id: String) -> DeviceMetadata {
        var metadata = DeviceMetadata()
        metadata.trackerInformation.deviceRegistration.canonicID.id = id
        metadata.trackerInformation.deviceRegistration.deviceDescription.userDefinedName = "Mein Tracker"
        metadata.trackerInformation.deviceRegistration.encryptedKeys.ownerKeyVersion = 1
        return metadata
    }
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor func testPartialAndUndecryptableUpdatesKeepWorkingKeysAndMetadata() async throws {
        let manager = TokenManager.sharedInstance
        let originalVersion = manager.ownerKeyVersion
        defer { manager.ownerKeyVersion = originalVersion }
        let ownerKey = Data(repeating: 0x11, count: 32)
        manager.ownerKeyVersion = 1
        let initial = metadata(id: "preserve-" + UUID().uuidString)
        let device = try XCTUnwrap(convertToLocalFindMyDevice(deviceMetadata: initial, existingDevices: [], ownerKey: ownerKey))
        let eik = Data(repeating: 0x22, count: 32)
        let accountKey = Data(repeating: 0x33, count: 16)
        device.eik = eik; device.accountKey = accountKey
        var partial = DeviceMetadata()
        partial.trackerInformation.deviceRegistration.canonicID.id = device.id
        XCTAssertTrue(convertToLocalFindMyDevice(deviceMetadata: partial, existingDevices: [device], ownerKey: ownerKey) === device)
        await drainMainQueue()
        XCTAssertEqual(device.eik, eik)
        XCTAssertEqual(device.accountKey, accountKey)
        XCTAssertEqual(device.userDefinedName, "Mein Tracker")
        var corrupt = initial
        corrupt.trackerInformation.deviceRegistration.encryptedKeys.encryptedIdentityKey = Data(repeating: 0, count: 60)
        _ = convertToLocalFindMyDevice(deviceMetadata: corrupt, existingDevices: [device], ownerKey: ownerKey)
        await drainMainQueue()
        XCTAssertEqual(device.eik, eik)
        XCTAssertEqual(device.accountKey, accountKey)
    }

    @MainActor func testOlderArchivedKeysCannotRollBackValidatedReplacement() async throws {
        let manager = TokenManager.sharedInstance
        let originalVersion = manager.ownerKeyVersion
        defer { manager.ownerKeyVersion = originalVersion }
        let ownerKey = Data(repeating: 0x44, count: 32)
        manager.ownerKeyVersion = 1
        var initial = metadata(id: "rotation-" + UUID().uuidString)
        let old = Data(repeating: 0x55, count: 32), latest = Data(repeating: 0x66, count: 32)
        initial.trackerInformation.deviceRegistration.encryptedKeys.creationDate.seconds = 100
        initial.trackerInformation.deviceRegistration.encryptedKeys.encryptedIdentityKey = try AESGCM.encrypt(key: ownerKey, plaintext: old)
        // This framework test runner has no signing/Keychain identity. Supply the
        // owner key directly so failures concern conversion rather than SecItemAdd.
        XCTAssertEqual(try EIKDecryptor.decrypt(ownerKey: ownerKey,
            encryptedEIK: initial.trackerInformation.deviceRegistration.encryptedKeys.encryptedIdentityKey,
            isObfuscated: false), old)
        let device = try XCTUnwrap(convertToLocalFindMyDevice(deviceMetadata: initial, existingDevices: [], ownerKey: ownerKey))
        XCTAssertEqual(device.eik, old)
        var replacement = initial
        replacement.trackerInformation.deviceRegistration.encryptedKeys.creationDate.seconds = 200
        replacement.trackerInformation.deviceRegistration.encryptedKeys.encryptedIdentityKey = try AESGCM.encrypt(key: ownerKey, plaintext: latest)
        _ = convertToLocalFindMyDevice(deviceMetadata: replacement, existingDevices: [device], ownerKey: ownerKey)
        await drainMainQueue()
        XCTAssertEqual(device.eik, latest)
        _ = convertToLocalFindMyDevice(deviceMetadata: initial, existingDevices: [device], ownerKey: ownerKey)
        await drainMainQueue()
        XCTAssertEqual(device.eik, latest)
        XCTAssertEqual(device.keyDate, Date(timeIntervalSince1970: 200))
    }

    func testTruncatedEncryptedReportsThrowWithoutCrashing() {
        let key = Data(repeating: 0, count: 32)
        for length in 0..<28 {
            XCTAssertThrowsError(try AESGCM.decrypt(key: key, encryptedDataAndIV: Data(repeating: 0, count: length)))
        }
    }
}
