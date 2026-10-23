//
//  UpdateBleDeviceSharingSettings.swift
//  Spot
//
//  Created by Leon Böttger on 20.01.25.
//

import CryptoKit
import Foundation
import LUI

private let scope = "UpdateBleDeviceSharingSettings"

class UpdateBleDeviceSharingSettings {
    static func createSharingLink(device: LocalFindMyDevice) async throws -> String {
        guard let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex else {
            throw NSError(domain: "Owner key not available", code: 1)
        }

        let canonicDeviceId = device.canonicDeviceId

        var request = UpdateBleDeviceSharingSettingsRequest()
        request.canonicID.id = canonicDeviceId

        request.sharingID = Int64.random(in: 0 ..< Int64.max)
        request.operation = .createInvite

        let newKeyPair = P256.KeyAgreement.PrivateKey()
        let publicKey = newKeyPair.publicKey.derRepresentation
        let privateKey = newKeyPair.derRepresentation

        var keyWrapper = PrivateKeyWrapper()
        keyWrapper.privateKey = privateKey
        keyWrapper.publicKey = publicKey
        let serializedKeyWrapper = try keyWrapper.serializedData()

        let encryptedKeyWrapper = try AESGCM.encrypt(key: ownerKey, plaintext: serializedKeyWrapper)
        request.encryptedPrivateKeyWrapper = encryptedKeyWrapper

        let serializedRequest = try request.serializedData()

        let _ = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)

        var invitationToken = InvitationToken()
        invitationToken.canonicID = canonicDeviceId.replacingOccurrences(of: "-", with: "").dataFromHex
        invitationToken.sharingID = request.sharingID
        invitationToken.ownerPublicKey = publicKey

        let serializedMetadata = try invitationToken.serializedData()
        let metadataAsBase64Url = dataToBase64URL(serializedMetadata)

        return "https://www.google.com/android/find/device/2?sharingInvitation=token#\(metadataAsBase64Url)"
    }

    static func retrieveInvitationFromLink(link: String) async throws -> SharingInvitation {
        let token = link.components(separatedBy: "#").last ?? ""
        let metadataAsBytes = base64UrlToData(base64UrlString: token)

        guard let metadataAsBytes else {
            throw NSError(domain: "URL Malformed!", code: 0, userInfo: nil)
        }

        let invitationToken = try InvitationToken(serializedBytes: metadataAsBytes)
        let sharingID = invitationToken.sharingID
        let canonicID = invitationToken.canonicID

        var request = UpdateBleDeviceSharingSettingsRequest()

        if canonicID.count == 16 {
            let uuid = canonicID.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> UUID in
                let uuidBytes = bytes.bindMemory(to: uuid_t.self)
                return UUID(uuid: uuidBytes[0])
            }

            request.canonicID.id = uuid.uuidString.lowercased()
        } else {
            throw NSError(domain: "Input data must be exactly 16 bytes to create a UUID.", code: 0, userInfo: nil)
        }

        request.operation = .retrieveInvitation
        request.sharingID = sharingID

        let serializedRequest = try request.serializedData()
        let response = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)

        let parsedResult = try UpdateBleDeviceSharingSettingsResponse(serializedBytes: response)
        let ownerEmail = parsedResult.accessInformation.first(where: { $0.isOwner })

        guard let ownerEmail else {
            throw NSError(domain: "Owner email not found", code: 0, userInfo: nil)
        }

        return SharingInvitation(deviceName: parsedResult.deviceRegistration.deviceDescription.userDefinedName, canonicID: request.canonicID.id, ownerEmail: ownerEmail.email, ownerPublicKey: invitationToken.ownerPublicKey, imageURL: parsedResult.deviceRegistration.deviceDescription.deviceComponentsInformation.first?.imageURL ?? "", sharingId: sharingID)
    }

    static func acceptInvitation(invitation: SharingInvitation) async throws -> String {
        guard let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex else {
            throw NSError(domain: "Owner key not available", code: 1)
        }

        let canonicDeviceId = invitation.canonicID

        var request = UpdateBleDeviceSharingSettingsRequest()
        request.canonicID.id = canonicDeviceId

        request.sharingID = invitation.sharingId
        request.operation = .acceptInvite

        let newKeyPair = P256.KeyAgreement.PrivateKey()
        let publicKey = newKeyPair.publicKey.derRepresentation
        let privateKey = newKeyPair.derRepresentation

        var keyWrapper = PrivateKeyWrapper()
        keyWrapper.privateKey = privateKey
        keyWrapper.publicKey = publicKey
        let serializedKeyWrapper = try keyWrapper.serializedData()

        let encryptedKeyWrapper = try AESGCM.encrypt(key: ownerKey, plaintext: serializedKeyWrapper)
        request.encryptedPrivateKeyWrapper = encryptedKeyWrapper

        request.encryptedUserSecrets.sharingKeys.inviteeKey = publicKey
        request.encryptedUserSecrets.sharingKeys.inviterKey = try AESGCM.encrypt(key: ownerKey, plaintext: invitation.ownerPublicKey)

        let pin = calculatePIN(ownerPublicKeyDER: invitation.ownerPublicKey, inviteePublicKeyDER: publicKey)

        let serializedRequest = try request.serializedData()

        let _ = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)

        return pin
    }

    static func calculatePIN(ownerPublicKeyDER: Data, inviteePublicKeyDER: Data) -> String {
        let appendedKeys = ownerPublicKeyDER + inviteePublicKeyDER
        let pin = SHA256.hash(data: appendedKeys).suffix(2).hex

        return pin.uppercased()
    }

    static func decryptEikAndAccountKeyFromSharedSecret(canonicDeviceID: String, encryptedEIK: Data, encryptedAccountKey: Data, creationDate: Time, ownerDER: Data, inviteePrivateKeyWrapper: PrivateKeyWrapper) throws -> (Data, Data) {
        let sharedSecret = try getSharedSecret(ownerPublicKeyDER: ownerDER, inviteePrivateKeyWrapper: inviteePrivateKeyWrapper)

        let accountKey = try AESGCM.decrypt(key: sharedSecret, encryptedDataAndIV: encryptedAccountKey)

        let identityKey = try AESGCM.decrypt(key: sharedSecret, encryptedDataAndIV: encryptedEIK)

        Task {
            do {
                try await uploadReencryptedKeys(canonicDeviceID: canonicDeviceID, EIK: identityKey, accountKey: accountKey, creationDate: creationDate)
            } catch {}

            // refresh device list
            refreshDeviceList()
        }

        return (identityKey, accountKey)
    }

    static func acceptInviteeAndUploadEncryptedKeys(canonicDeviceID: String, EIK: Data, accountKey: Data, inviteeAccount: String, creationDate: Date, inviteeDER: Data, ownerPrivateKeyWrapper: PrivateKeyWrapper) async throws {
        let sharedSecret = try getSharedSecret(inviteePublicKeyDER: inviteeDER, ownerPrivateKeyWrapper: ownerPrivateKeyWrapper)

        var request = UpdateBleDeviceSharingSettingsRequest()
        request.operation = .uploadKeys
        request.canonicID.id = canonicDeviceID

        request.updateForAccount = inviteeAccount

        request.encryptedUserSecrets.encryptedIdentityKey = try AESGCM.encrypt(key: sharedSecret, plaintext: EIK)
        request.encryptedUserSecrets.encryptedAccountKey = try AESGCM.encrypt(key: sharedSecret, plaintext: accountKey)
        request.encryptedUserSecrets.creationDate.seconds = creationDate.unixTime

        request.encryptedUserSecrets.encryptedWithSharedSecret = true

        let serializedRequest = try request.serializedData()
        _ = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)
    }

    private static func getSharedSecret(ownerPublicKeyDER: Data, inviteePrivateKeyWrapper: PrivateKeyWrapper) throws -> Data {
        let ownerPublicKey = try P256.KeyAgreement.PublicKey(derRepresentation: ownerPublicKeyDER)
        let ownPrivateKey = try P256.KeyAgreement.PrivateKey(derRepresentation: inviteePrivateKeyWrapper.privateKey)

        let sharedSecret = try SymmetricKey(data: ownPrivateKey.sharedSecretFromKeyAgreement(with: ownerPublicKey)).withUnsafeBytes { Data($0) }

        let appendedKeys = ownerPublicKeyDER + inviteePrivateKeyWrapper.publicKey + sharedSecret

        return SHA256.hash(data: appendedKeys)
    }

    private static func getSharedSecret(inviteePublicKeyDER: Data, ownerPrivateKeyWrapper: PrivateKeyWrapper) throws -> Data {
        let inviteePublicKey = try P256.KeyAgreement.PublicKey(derRepresentation: inviteePublicKeyDER)
        let ownPrivateKey = try P256.KeyAgreement.PrivateKey(derRepresentation: ownerPrivateKeyWrapper.privateKey)

        let sharedSecret = try SymmetricKey(data: ownPrivateKey.sharedSecretFromKeyAgreement(with: inviteePublicKey)).withUnsafeBytes { Data($0) }

        let appendedKeys = ownerPrivateKeyWrapper.publicKey + inviteePublicKeyDER + sharedSecret

        return SHA256.hash(data: appendedKeys)
    }

    private static func uploadReencryptedKeys(canonicDeviceID: String, EIK: Data, accountKey: Data, creationDate: Time) async throws {
        guard let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex else {
            throw NSError(domain: "Owner key not available", code: 1)
        }

        let reencryptedIdentityKey = try AESGCM.encrypt(key: ownerKey, plaintext: EIK)
        let reencryptedAccountKey = try AESGCM.encrypt(key: ownerKey, plaintext: accountKey)

        var request = UpdateBleDeviceSharingSettingsRequest()
        request.operation = .uploadReencryptedKeys
        request.canonicID.id = canonicDeviceID

        request.encryptedUserSecrets.encryptedIdentityKey = reencryptedIdentityKey
        request.encryptedUserSecrets.encryptedAccountKey = reencryptedAccountKey
        request.encryptedUserSecrets.ownerKeyVersion = Int32(TokenManager.sharedInstance.ownerKeyVersion)
        request.encryptedUserSecrets.creationDate = creationDate

        let serializedRequest = try request.serializedData()
        _ = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)
    }

    static func stopSharing(canonicDeviceID: String, removedAccount: String? = nil) async throws {
        var request = UpdateBleDeviceSharingSettingsRequest()
        request.operation = .stopSharing
        request.canonicID.id = canonicDeviceID

        if let removedAccount {
            request.updateForAccount = removedAccount
        }

        let serializedRequest = try request.serializedData()
        _ = try await SpotApiManager.spotRequest(apiScope: scope, payload: serializedRequest)
    }
}

struct SharingInvitation {
    let deviceName: String
    let canonicID: String
    let ownerEmail: String
    let ownerPublicKey: Data
    let imageURL: String
    let sharingId: Int64
}
