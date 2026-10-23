//
//  HKDF.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import CryptoKit
import Foundation

class HKDF {
    static func deriveKey(secret: SymmetricKey, salt: Data, info: Data, outputLength: Int) throws -> Data {
        // Ensure the output length is valid
        guard outputLength > 0 else {
            throw NSError(domain: "InvalidOutputLength", code: 0, userInfo: [NSLocalizedDescriptionKey: "The output length must be greater than 0!"])
        }

        // Perform key derivation
        let hkdfKey = CryptoKit.HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: secret,
            salt: salt,
            info: info,
            outputByteCount: outputLength
        )

        // Convert the derived key back to Data
        return hkdfKey.withUnsafeBytes { Data($0) }
    }
}
