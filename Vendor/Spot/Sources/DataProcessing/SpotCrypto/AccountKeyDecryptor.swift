//
//  AccountKeyDecryptor.swift
//  Spot
//
//  Created by Leon Böttger on 14.12.24.
//

import Foundation
import Combine

class AccountKeyDecryptor {
    static func decrypt(ownerKey: Data, encryptedAccountKey: Data) throws -> Data {
        try AESGCM.decrypt(key: ownerKey, encryptedDataAndIV: encryptedAccountKey)
    }

    static func decryptUsingDeviceUpdate(deviceUpdate: DeviceUpdate) throws -> Data {
        let ownerKey = TokenManager.sharedInstance.ownerKey

        guard let ownerKey else {
            throw NSError(domain: "OwnerKeyNil", code: 0, userInfo: [NSLocalizedDescriptionKey: "Owner key is nil!"])
        }

        let information = getInformation(deviceMetadata: deviceUpdate.deviceMetadata)

        return try decrypt(ownerKey: ownerKey.dataFromHex, encryptedAccountKey: information.deviceRegistration.encryptedKeys.encryptedAccountKey)
    }
}
