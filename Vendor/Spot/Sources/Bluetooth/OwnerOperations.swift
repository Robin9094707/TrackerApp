//
//  OwnerOperations.swift
//
//
//  Created by Leon Böttger on 23.12.24.
//

import CommonCrypto
import CryptoKit
import Foundation
import LUI
import SwiftUI

class FMDNOwnerOperations: ObservableObject {
    static func executeReadStateOperation(currentBluetoothId: String, accountKey: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        let resultCallback: (BluetoothRequestState, Data?) -> Void = { state, data in
            guard let data else {
                callback(state, nil)
                return
            }

            let bytes = Array(data)

            // Drop length and authentication data
            let encryptedState = Array(bytes.dropFirst(10))

            do {
                let decryptedBytes = try AESECB.decrypt(data: Data(encryptedState), key: accountKey)

                // Remove AES padding and generate string
                let decryptedHex = Data(decryptedBytes.dropLast(8))

                callback(state, decryptedHex)
            } catch {
                callback(.Failure, nil)
            }
        }

        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: resultCallback) { [self] authenticationData in
            return makeReadBeaconParameters(authenticationData: authenticationData, accountKey: accountKey)
        }
    }

    static func executeRingerOperation(currentBluetoothId: String, eik: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        let ringingKey = RegisterBleDeviceKeyGen.getRingingKey(eik: eik)

        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeRingTrackerOperationData(authenticationData: authenticationData, operationKey: ringingKey)
        }
    }

    static func executeEikRecoveryOperation(currentBluetoothId: String, eik: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        let recoveryKey = RegisterBleDeviceKeyGen.getRecoveryKey(eik: eik)

        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeEikKeyRecoveryOperation(authenticationData: authenticationData, operationKey: recoveryKey)
        }
    }

    static func executeEnableUnwantedTrackingProtectionOperation(currentBluetoothId: String, eik: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        let trackingKey = RegisterBleDeviceKeyGen.getUnwantedTrackingKey(eik: eik)

        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeEnableUnwantedTrackingModeOperation(authenticationData: authenticationData, operationKey: trackingKey)
        }
    }

    static func executeDisableUnwantedTrackingProtectionOperation(currentBluetoothId: String, eik: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        let trackingKey = RegisterBleDeviceKeyGen.getUnwantedTrackingKey(eik: eik)

        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeDisableUnwantedTrackingModeOperation(authenticationData: authenticationData, eik: eik, operationKey: trackingKey)
        }
    }

    static func executeWriteEikOperation(currentBluetoothId: String, newEik: Data, oldEik: Data?, accountKey: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeWriteEikOperation(authenticationData: authenticationData, newEik: newEik, oldEik: oldEik, operationKey: accountKey)
        }
    }

    static func executeUnpairOperation(currentBluetoothId: String, eik: Data, accountKey: Data, callback: @escaping (BluetoothRequestState, Data?) -> Void) {
        executeFmdnOperation(currentBluetoothId: currentBluetoothId, resultCallback: callback) { [self] authenticationData in
            return makeUnpairOperation(authenticationData: authenticationData, eik: eik, operationKey: accountKey)
        }
    }

    static func executeFmdnOperation(currentBluetoothId: String, resultCallback: @escaping (BluetoothRequestState, Data?) -> Void = { _, _ in }, constructOperationData: @escaping (Data) -> Data?) {
        let fastPairService = Constants.FastPairService
        let fastPairCharacteristic = Constants.FastPairBeaconActionsCharacteristic
        let request = BluetoothRequest.readCharacteristic(deviceID: currentBluetoothId, serviceID: fastPairService, characteristicID: fastPairCharacteristic, stayConnected: true) { state, data in
            if let data, let payloadData = constructOperationData(data) {
                let request2 = BluetoothRequest.writeReadCharacteristic(deviceID: currentBluetoothId, serviceID: fastPairService, characteristicID: fastPairCharacteristic, data: payloadData) { state, data in
                    resultCallback(state, data)
                }

                BluetoothManager.sharedInstance.addRequest(request: request2)
            } else {
                resultCallback(state, nil)
            }
        }

        BluetoothManager.sharedInstance.addRequest(request: request)
    }

    private static func makeEikKeyRecoveryOperation(authenticationData: Data, operationKey: Data) -> Data? {
        // Opcode for EIK key recovery
        let dataID: UInt8 = 0x04

        return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: Data())
    }

    private static func makeEnableUnwantedTrackingModeOperation(authenticationData: Data, operationKey: Data) -> Data? {
        // Opcode for enabling UT tracking mode
        let dataID: UInt8 = 0x07

        return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: Data([0x01]))
    }

    private static func makeDisableUnwantedTrackingModeOperation(authenticationData: Data, eik: Data, operationKey: Data) -> Data? {
        // Opcode for disabling UT tracking mode
        let dataID: UInt8 = 0x08

        let nonce = splitAuthenticationData(authenticationData: authenticationData).1
        let additionalData = RegisterBleDeviceKeyGen.calculateTruncatedSHA256(identityKey: eik, operation: nonce)

        return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: additionalData)
    }

    private static func makeWriteEikOperation(authenticationData: Data, newEik: Data, oldEik: Data?, operationKey: Data) -> Data? {
        // Opcode for writing EIK
        let dataID: UInt8 = 0x02

        do {
            var additionalData = try AESECB.encrypt(data: newEik, key: operationKey)

            if additionalData.count != 32 {
                return nil
            }

            // Tracker already provisioned => also send old EIK for verification
            if let oldEik {
                let nonce = splitAuthenticationData(authenticationData: authenticationData).1
                let oldEikHash = RegisterBleDeviceKeyGen.calculateTruncatedSHA256(identityKey: oldEik, operation: nonce)
                additionalData.append(oldEikHash)
            }

            return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: additionalData)
        } catch {}

        return nil
    }

    private static func makeUnpairOperation(authenticationData: Data, eik: Data, operationKey: Data) -> Data? {
        // Opcode for removing EIK
        let dataID: UInt8 = 0x03

        let nonce = splitAuthenticationData(authenticationData: authenticationData).1
        let additionalData = RegisterBleDeviceKeyGen.calculateTruncatedSHA256(identityKey: eik, operation: nonce)

        return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: additionalData)
    }

    private static func makeReadBeaconParameters(authenticationData: Data, accountKey: Data) -> Data? {
        // Opcode for reading beacon parameters
        let dataID: UInt8 = 0x00

        return constructOperationData(authenticationData: authenticationData, operationKey: accountKey, dataID: dataID)
    }

    private static func makeRingTrackerOperationData(authenticationData: Data, operationKey: Data) -> Data? {
        // Data ID for "Ring"
        let dataID: UInt8 = 0x05

        // Additional data is always 0xFF025800
        let additionalData: [UInt8] = [0xFF, 0x02, 0x58, 0x00]

        return constructOperationData(authenticationData: authenticationData, operationKey: operationKey, dataID: dataID, additionalData: Data(additionalData))
    }

    private static func splitAuthenticationData(authenticationData: Data) -> (UInt8, Data) {
        let protocolMajorVersion = authenticationData[0]
        let nonce = authenticationData.subdata(in: 1 ..< 9)

        return (protocolMajorVersion, nonce)
    }

    private static func constructOperationData(authenticationData: Data, operationKey: Data, dataID: UInt8, additionalData: Data? = nil) -> Data? {
        let split = splitAuthenticationData(authenticationData: authenticationData)

        let protocolMajorVersion = split.0
        let nonce = split.1

        // Data length includes the length of the MAC and additional data
        let dataLength = UInt8(8 + (additionalData?.count ?? 0))

        // Compute HMAC-SHA256
        var message = Data()
        message.append(protocolMajorVersion)
        message.append(nonce)
        message.append(dataID)
        message.append(dataLength)

        if let additionalData {
            message.append(contentsOf: additionalData)
        }

        var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        hmac.withUnsafeMutableBytes { hmacBytes in
            message.withUnsafeBytes { messageBytes in
                operationKey.withUnsafeBytes { operationKeyBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), operationKeyBytes.baseAddress, operationKey.count, messageBytes.baseAddress, message.count, hmacBytes.baseAddress)
                }
            }
        }

        // Take the first 8 bytes of the HMAC
        let oneTimeAuthKey = hmac.prefix(8)

        // Construct the final data object
        var dataObject = Data()
        dataObject.append(dataID)
        dataObject.append(dataLength)
        dataObject.append(oneTimeAuthKey)

        if let additionalData {
            dataObject.append(contentsOf: additionalData)
        }

        return dataObject
    }
}
