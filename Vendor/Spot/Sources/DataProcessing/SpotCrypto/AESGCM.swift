//
//  AESGCM.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import CryptoKit
import Foundation
import LUI
import SwiftUI

class AESGCM {
    static func decrypt(key: Data, encryptedDataAndIV: Data, ivLength: Int = 12) throws -> Data {
        let iv = encryptedDataAndIV.prefix(ivLength)
        let ciphertextAndTag = encryptedDataAndIV.dropFirst(ivLength)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.prefix(ciphertextAndTag.count - 16)

        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
    }

    static func encrypt(key: Data, plaintext: Data, iv: Data? = nil) throws -> Data {
        var iv = iv

        if iv == nil {
            iv = try getIV()
        }

        guard let iv, let nonce = try? AES.GCM.Nonce(data: iv) else {
            throw NSError(domain: "InvalidIV", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid IV!"])
        }

        // Perform AES-GCM encryption
        let sealedBox = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce)

        // Combine IV, ciphertext, and authentication tag
        return iv + sealedBox.ciphertext + sealedBox.tag
    }

    static func getIV(with length: Int = 12) throws -> Data {
        try SecureRandom.getBytes(length)
    }
}
