//
//  FcmDecryptor.swift
//  Spot
//
//  Created by Leon Böttger on 08.12.24.
//

import CryptoKit
import Foundation
import Combine

class FcmDecryptor {
    static func decryptRawData(
        rawData: Data,
        serverPublicKeyString: String,
        saltString: String,
        ownPrivateKeyDer: String,
        ownSecretString: String
    ) throws -> Data {
        let remoteDhCryptoKey = base64UrlToData(base64UrlString: serverPublicKeyString)
        let salt = base64UrlToData(base64UrlString: saltString)
        let ownPrivateKeyDerData = base64UrlToData(base64UrlString: ownPrivateKeyDer)
        let secret = base64UrlToData(base64UrlString: ownSecretString)

        guard let remoteDhCryptoKey, let salt, let ownPrivateKeyDerData, let secret else {
            throw NSError(domain: "Failed to decode base64 data", code: 0, userInfo: nil)
        }

        let privateKey = try P256.KeyAgreement.PrivateKey(derRepresentation: ownPrivateKeyDerData)

        // strip prefix (0x04) from remoteDhCrypto
        let x = remoteDhCryptoKey.subdata(in: 1 ..< 33) // First 32 bytes after the prefix
        let y = remoteDhCryptoKey.subdata(in: 33 ..< 65) // Next 32 bytes

        let keyData = x + y
        let publicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: keyData)

        return try httpDecrypt(rawData: rawData, salt: salt, privateKey: privateKey, publicKey: publicKey, authSecret: secret)
    }

    private static func httpDecrypt(rawData: Data, salt: Data, privateKey: P256.KeyAgreement.PrivateKey, publicKey: P256.KeyAgreement.PublicKey, authSecret: Data) throws -> Data {
        let chunk = 4096 + 16 // 16 Bytes for tags

        let (key, nonce) = try deriveKey(salt: salt, privateKey: privateKey, publicKey: publicKey, authSecret: authSecret)

        var result = Data()
        var counter: UInt64 = 0

        for i in stride(from: 0, to: rawData.count, by: chunk) {
            let data = try decryptRecord(key: key, nonce: nonce, counter: counter, content: rawData.subdata(in: i ..< min(i + chunk, rawData.count)))
            try result.append(unpadLegacy(data: data))
            counter += 1
        }

        return result
    }

    private static func decryptRecord(key: Data, nonce: Data, counter: UInt64, content: Data) throws -> Data {
        let TAG_LENGTH = 16

        let tagRange = content.index(content.endIndex, offsetBy: -TAG_LENGTH) ..< content.endIndex
        let tag = content.subdata(in: tagRange)
        let ciphertext = content.subdata(in: 0 ..< content.index(content.endIndex, offsetBy: -TAG_LENGTH))

        let iv = try iv(base: nonce, counter: counter)

        let decryptor = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(decryptor, using: SymmetricKey(data: key))
    }

    private static func iv(base: Data, counter: UInt64) throws -> Data {
        guard counter >> 64 == 0 else {
            throw NSError(domain: "Counter too big!", code: 0, userInfo: nil)
        }
        let mask = base.subdata(in: 4 ..< 12).withUnsafeBytes { $0.load(as: UInt64.self) }
        var result = base.subdata(in: 0 ..< 4)
        result.append(Data(from: counter ^ mask))
        return result
    }

    private static func unpadLegacy(data: Data) throws -> Data {
        let padSize = 2
        let padBytes = data.prefix(padSize)
        let pad = padBytes.reduce(0) { ($0 << 8) | Int($1) }

        if padSize + pad > data.count || data[padSize ..< (padSize + pad)] != Data(repeating: 0, count: pad) {
            throw NSError(domain: "Failed to unpad data", code: 0, userInfo: nil)
        }

        return data.dropFirst(padSize + pad)
    }

    private static func deriveKey(salt: Data, privateKey: P256.KeyAgreement.PrivateKey, publicKey: P256.KeyAgreement.PublicKey, authSecret: Data) throws -> (Data, Data) {
        let (sharedSecret, context) = try deriveDH(privateKey: privateKey, dh: publicKey)

        let keyinfo = buildInfo(base: "aesgcm", infoContext: context)
        let nonceinfo = buildInfo(base: "nonce", infoContext: context)
        let info = buildInfo(base: "auth", infoContext: Data())

        let hkdfAuth = try HKDF.deriveKey(secret: SymmetricKey(data: sharedSecret), salt: authSecret, info: info, outputLength: 32)

        let hkdfKey = try HKDF.deriveKey(secret: SymmetricKey(data: hkdfAuth), salt: salt, info: keyinfo, outputLength: 16)
        let hkdfNonce = try HKDF.deriveKey(secret: SymmetricKey(data: hkdfAuth), salt: salt, info: nonceinfo, outputLength: 12)

        return (hkdfKey, hkdfNonce)
    }

    private static func buildInfo(base: String, infoContext: Data) -> Data {
        let baseData = base.data(using: .utf8)!
        return "Content-Encoding: ".data(using: .utf8)! + baseData + Data([0]) + infoContext
    }

    private static func deriveDH(privateKey: P256.KeyAgreement.PrivateKey, dh: P256.KeyAgreement.PublicKey) throws -> (SharedSecret, Data) {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: dh)
        let context = getContext(receiverPrivateKey: privateKey, senderPubKey: dh)

        return (sharedSecret, context)
    }

    private static func getContext(receiverPrivateKey: P256.KeyAgreement.PrivateKey, senderPubKey: P256.KeyAgreement.PublicKey) -> Data {
        let keyLabel = "P-256"
        let receiverPublicKey = receiverPrivateKey.publicKey

        // 4 to indicate that the key is uncompressed
        let receiverPublicKeyBytes = Data([4]) + receiverPublicKey.rawRepresentation
        let senderPublicKeyBytes = Data([4]) + senderPubKey.rawRepresentation

        let context = keyLabel.data(using: .utf8)! + Data([0]) +
            lengthPrefix(key: receiverPublicKeyBytes) +
            lengthPrefix(key: senderPublicKeyBytes)

        func lengthPrefix(key: Data) -> Data {
            var length = UInt16(key.count).bigEndian
            var data = Data(bytes: &length, count: MemoryLayout.size(ofValue: length))
            data.append(key)
            return data
        }

        return context
    }
}

private extension Data {
    init(from value: some Any) {
        var value = value
        self = Swift.withUnsafeBytes(of: &value) { Data($0) }
    }
}
