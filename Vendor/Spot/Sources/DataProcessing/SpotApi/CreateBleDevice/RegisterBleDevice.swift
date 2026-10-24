//
//  RegisterBleDevice.swift
//
//
//  Created by Leon Böttger on 19.12.24.
//

import Foundation
import Combine

enum RegisterBleDevice {
    static func registerESP32(pairDate: Int32, ownerKey: Data, EIK: Data, curveType: CurveType) async throws -> DeviceMetadata.DeviceInformation {
        let accountKey = try RegisterBleDeviceKeyGen.createAccountKey()
        let secrets = try RegisterBleDeviceKeyGen.generateE2EEKeys(
            eik: EIK, accountKey: accountKey, curveType: .secp160r1, pairDate: pairDate,
            eidLimitSeconds: Int(hoursToSeconds(hours: 2)), isCustomTracker: true
        )

        var request = RegisterBleDeviceRequest()
        request.fastPairModelID = esp32Id
        request.description_p.userDefinedName = "ESP32 Device"
        request.description_p.deviceType = .deviceTypeBeacon
        request.description_p.beaconType = .beaconTypeDefaultTag

        var componentInformation = DeviceComponentInformation()
        componentInformation.deviceComponent = .unspecified
        componentInformation.imageURL = "https://docs.espressif.com/projects/esp-idf/en/v4.3/esp32/_images/esp32-DevKitM-1-isometric.png"
        request.description_p.deviceComponentsInformation = [componentInformation]

        request.capabilities.isAdvertising = true
        request.capabilities.ringingVolumeSupported = false
        request.capabilities.trackableComponents = 1
        request.capabilities.capableComponents = 1

        request.e2EePublicKeyRegistration.rotationExponent = 10
        request.e2EePublicKeyRegistration.deviceEncryptionScheme = curveType == .secp160r1 ? .eid20Bytes : .eid32Bytes
        request.e2EePublicKeyRegistration.pairingDate = pairDate
        request.e2EePublicKeyRegistration.encryptedUserSecrets.encryptedIdentityKey = try AESGCM.encrypt(key: ownerKey, plaintext: secrets.eik).bitFlipped(enabled: true)
        request.e2EePublicKeyRegistration.encryptedUserSecrets.encryptedAccountKey = try AESGCM.encrypt(key: ownerKey, plaintext: secrets.accountKey)
        request.e2EePublicKeyRegistration.encryptedUserSecrets.encryptedSha256AccountKeyPublicAddress = try AESGCM.encrypt(key: ownerKey, plaintext: secrets.sha256AccountKeyPublicAddress)
        request.e2EePublicKeyRegistration.encryptedUserSecrets.ownerKeyVersion = Int32(TokenManager.sharedInstance.ownerKeyVersion)
        request.e2EePublicKeyRegistration.encryptedUserSecrets.creationDate.seconds = Date().unixTime

        for eid in secrets.eids {
            var publicKeyID = PublicKeyIdList.PublicKeyIdInfo()
            publicKeyID.publicKeyID.truncatedEid = TruncatedEID.fromEID(eid.eid)
            publicKeyID.timestamp.seconds = eid.timestamp
            request.e2EePublicKeyRegistration.publicKeyIDList.publicKeyIDInfo.append(publicKeyID)
        }

        request.manufacturerName = "Espressif"
        request.ringKey = secrets.ringingKey
        request.recoveryKey = secrets.recoveryKey
        request.unwantedTrackingKey = secrets.unwantedTrackingKey
        request.modelName = "ESP32"

        let result = try await SpotApiManager.spotRequest(apiScope: "CreateBleDevice", payload: request.serializedData())
        try UploadPrecomputedPublicKeyIds.sharedInstance.checkAndUpload()
        return try DeviceMetadata.DeviceInformation(serializedBytes: result)
    }
}
