//
//  AESCTR.swift
//  Spot
//
//  Created by Leon Böttger on 16.12.24.
//

import CryptoSwift
import Foundation

class AESCTR {
    static func encrypt(key: Data, nonce: Data, data: Data) throws -> Data {
        let aes = try AES(key: key.bytes, blockMode: CTR(iv: nonce.bytes), padding: .noPadding)
        let encrypted = try aes.encrypt(data.bytes)
        return Data(encrypted)
    }

    static func decrypt(key: Data, nonce: Data, data: Data) throws -> Data {
        let aes = try AES(key: key.bytes, blockMode: CTR(iv: nonce.bytes), padding: .noPadding)
        let encrypted = try aes.decrypt(data.bytes)
        return Data(encrypted)
    }
}
