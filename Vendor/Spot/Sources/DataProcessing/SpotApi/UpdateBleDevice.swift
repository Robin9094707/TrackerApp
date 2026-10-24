//
//  UpdateBleDevice.swift
//  Spot
//
//  Created by Leon Böttger on 15.01.25.
//

import Foundation
import Combine

class UpdateBleDevice {
    static func setLostMode(canonicDeviceId: String, lostMode: Bool) async throws {
        var request = UpdateBleDeviceRequest()
        request.value.lostMode.enableLostMode = lostMode

        _ = try await perform(canonicDeviceId: canonicDeviceId, scope: "lost_info.lost_state", request: request)
    }

    static func setLostModeInfo(canonicDeviceId: String, phoneNumber: Int, message: String, email: String) async throws {
        var request = UpdateBleDeviceRequest()
        request.value.description_p.contactInfo.phoneNumber = String(phoneNumber)
        request.value.description_p.contactInfo.infoMessage = message
        request.value.description_p.contactInfo.email = email

        _ = try await perform(canonicDeviceId: canonicDeviceId, scope: "description.contact_info", request: request)
    }

    static func setDeviceInfo(canonicDeviceId: String, userDefinedName: String, imageURL: String, type: SpotDeviceType = .deviceTypeBeacon) async throws {
        var componentInformation = DeviceComponentInformation()
        componentInformation.deviceComponent = .unspecified
        componentInformation.imageURL = imageURL

        var request = UpdateBleDeviceRequest()
        request.value.description_p.userDefinedName = userDefinedName
        request.value.description_p.deviceType = type
        request.value.description_p.deviceComponentsInformation = [componentInformation]

        _ = try await perform(canonicDeviceId: canonicDeviceId, scope: "description", request: request)
    }

    static func setEncryptedUserSecrets(canonicDeviceId: String, EIK: Data, accountKey: Data, creationDate: Time) async throws {
        guard let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex else {
            return
        }

        let ownerKeyVersion = TokenManager.sharedInstance.ownerKeyVersion

        var request = UpdateBleDeviceRequest()
        request.value.encryptedUserSecrets.encryptedIdentityKey = try AESGCM.encrypt(key: ownerKey, plaintext: EIK)
        request.value.encryptedUserSecrets.encryptedAccountKey = try AESGCM.encrypt(key: ownerKey, plaintext: accountKey)
        request.value.encryptedUserSecrets.creationDate = creationDate
        request.value.encryptedUserSecrets.ownerKeyVersion = Int32(ownerKeyVersion)

        _ = try await perform(canonicDeviceId: canonicDeviceId, scope: "encrypted_user_secrets", request: request)
    }

    private static func perform(canonicDeviceId: String, scope: String, request: UpdateBleDeviceRequest) async throws -> Data {
        var request = request

        request.value.canonicID.id = canonicDeviceId
        request.scope.scope = scope

        let serializedProto = try request.serializedData()

        return try await SpotApiManager.spotRequest(apiScope: "UpdateBleDevice", payload: serializedProto)
    }
}
