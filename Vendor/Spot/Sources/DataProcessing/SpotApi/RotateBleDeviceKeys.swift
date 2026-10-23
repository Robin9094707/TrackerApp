//
//  RotateBleDeviceKeys.swift
//
//
//  Created by Leon Böttger on 18.01.25.
//

import Foundation
import LUI

enum RotateBleDeviceKeys {
    static func perform(localDevice: LocalFindMyDevice) async throws {
        guard let encryptedKeys = localDevice.encryptedKeys, let eik = localDevice.eik, let accountKey = localDevice.accountKey else {
            throw NSError(domain: "No encrypted keys found!", code: 0, userInfo: nil)
        }

        let keys = try RegisterBleDeviceKeyGen.generateE2EEKeys(eik: eik, accountKey: accountKey, curveType: localDevice.curveType, pairDate: localDevice.pairDate.unixTime, eidLimitSeconds: Int(hoursToSeconds(hours: 3)), isCustomTracker: localDevice.isCustomTracker)

        var requestProto = RotateBleDeviceKeysRequest()
        requestProto.canonicID.id = localDevice.canonicDeviceId

        requestProto.rotatedUserSecrets.encryptedUserSecrets.creationDate.seconds = Date().unixTime
        requestProto.rotatedUserSecrets.encryptedUserSecrets.encryptedAccountKey = encryptedKeys.encryptedAccountKey
        requestProto.rotatedUserSecrets.encryptedUserSecrets.encryptedIdentityKey = encryptedKeys.encryptedIdentityKey
        requestProto.rotatedUserSecrets.encryptedUserSecrets.encryptedSha256AccountKeyPublicAddress = encryptedKeys.encryptedSha256AccountKeyPublicAddress
        requestProto.rotatedUserSecrets.encryptedUserSecrets.ownerKeyVersion = Int32(TokenManager.sharedInstance.ownerKeyVersion)

        requestProto.rotatedUserSecrets.ringKey = keys.ringingKey
        requestProto.rotatedUserSecrets.recoveryKey = keys.recoveryKey
        requestProto.rotatedUserSecrets.unwantedTrackingKey = keys.unwantedTrackingKey

        requestProto.rotatedUserSecrets.pairDate = localDevice.pairDate.unixTime

        let serializedProto = try requestProto.serializedData()

        let result = try await SpotApiManager.spotRequest(apiScope: "RotateBleDeviceKeys", payload: serializedProto)
    }
}
