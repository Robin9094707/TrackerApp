//
//  ServerPublicKeyEncryptor.swift
//  Spot
//
//  Created by Leon Böttger on 16.12.24.
//

import BigInt
import CryptoKit
import Foundation
import SwiftECC
import SwiftUI

class ServerPublicKeyEncryptor {
    static func encrypt(googlePublicKey: GooglePublicKeys.EciesAeadHkdfPublicKeys.EciesAeadHkdfPublicKey, plaintext: Data) throws -> Data {
        let x = BInt(magnitude: Bytes(googlePublicKey.keyInformation.material.x))
        let y = BInt(magnitude: Bytes(googlePublicKey.keyInformation.material.y))

        let curve = Domain.instance(curve: .EC256r1)
        let serverPublicKey = try ECPublicKey(domain: curve, w: Point(x, y))

        let newKeyPair = curve.makeKeyPair()
        let newSecretKey = newKeyPair.1
        let newPublicKey = newKeyPair.0

        let newPublicKeyRaw = ensureDataLength(Data(newPublicKey.w.x.asMagnitudeBytes()), length: 32) + ensureDataLength(Data(newPublicKey.w.y.asMagnitudeBytes()), length: 32)
        let sharedSecret = try ensureDataLength(Data(newSecretKey.sharedSecret(pubKey: serverPublicKey)), length: 32)

        let keyToHash = newPublicKeyRaw + sharedSecret
        let aesGcmKey = try HKDF.deriveKey(secret: SymmetricKey(data: keyToHash), salt: Data(), info: Data(), outputLength: 16)

        let crunchyOrTink = Data([0])
        let keyIdentifier = int32ToData(googlePublicKey.keyIdentifier)
        let ciphertext = try AESGCM.encrypt(key: aesGcmKey, plaintext: plaintext)

        return crunchyOrTink + keyIdentifier + newPublicKeyRaw + ciphertext
    }
}
