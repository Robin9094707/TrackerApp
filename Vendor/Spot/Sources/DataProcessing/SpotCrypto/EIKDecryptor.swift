//
//  EIKDecryptor.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import CryptoKit
import Foundation
import LUI
import SwiftUI

class EIKDecryptor {
    static func decryptUsingDeviceRegistration(deviceRegistration: DeviceRegistration) throws -> Data {
        let encryptedIdentityKey = deviceRegistration.encryptedKeys.encryptedIdentityKey
        let ownerKey = TokenManager.sharedInstance.ownerKey
        let isCustom = deviceRegistration.fastPairModelID == esp32Id

        guard let ownerKey else {
            throw NSError(domain: "OwnerKeyNil", code: 0, userInfo: [NSLocalizedDescriptionKey: "Owner key is nil!"])
        }

        return try EIKDecryptor.decrypt(ownerKey: ownerKey.dataFromHex, encryptedEIK: encryptedIdentityKey, isObfuscated: isCustom)
    }

    static func decryptUsingDeviceUpdate(deviceUpdate: DeviceUpdate) throws -> Data {
        let information = getInformation(deviceMetadata: deviceUpdate.deviceMetadata)

        return try decryptUsingDeviceRegistration(deviceRegistration: information.deviceRegistration)
    }

    static func decrypt(ownerKey: Data, encryptedEIK: Data, isObfuscated: Bool) throws -> Data {
        // The EIK is encrypted using the owner key. The EIK is only valid for a certain tracker
        if encryptedEIK.count == 48 {
            throw NSError(domain: "InvalidEIKLength", code: 0, userInfo: [NSLocalizedDescriptionKey: "This key length is not implemented yet!"])
        }

        if encryptedEIK.count == 60 {
            return try AESGCM.decrypt(key: ownerKey, encryptedDataAndIV: encryptedEIK.bitFlipped(enabled: isObfuscated))
        }

        throw NSError(domain: "InvalidEIKLength", code: 0, userInfo: [NSLocalizedDescriptionKey: "The encrypted EIK has invalid length: \(encryptedEIK.count)!"])
    }
}
