//
//  AESEAX.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import CommonCrypto
import CryptoKit
import CryptoSwift
import Foundation
import Combine
import SwiftUI

class AESEAX {
    static func encrypt(key: Data, nonce: Data, plaintext: Data, associatedData: Data = Data(), tagLength: Int = 16) throws -> (ciphertext: Data, tag: Data) {
        // Validate key and nonce sizes
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else {
            throw NSError(domain: "InvalidKeySize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid key size. Use 128-bit or 256-bit key."])
        }
        guard nonce.count == kCCBlockSizeAES128 else {
            throw NSError(domain: "InvalidNonceSize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid nonce size. Use 128-bit nonce."])
        }

        // Step 1: Compute the nonce CMAC (n)
        let n = try calcOMAC(key: key, prefix: 0, message: nonce)

        // Step 2: Encrypt the plaintext using AES-CTR with nonce n
        let ciphertext = try AESCTR.encrypt(key: key, nonce: n, data: plaintext)

        // Step 3: Compute CMACs for associated data h and ciphertext c
        let h = try calcOMAC(key: key, prefix: 1, message: associatedData)
        let c = try calcOMAC(key: key, prefix: 2, message: ciphertext)

        // Step 4: Compute the authentication tag
        let tagDash = xorWithPadding(data1: xorWithPadding(data1: n, data2: h), data2: c)

        // Truncate the tag to match the length (16 bytes)
        let tag = tagDash.prefix(tagLength)

        // Return the ciphertext and authentication tag
        return (ciphertext, tag)
    }

    static func decrypt(key: Data, nonce: Data, ciphertext: Data, tag: Data, associatedData: Data = Data()) throws -> Data {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else {
            throw NSError(domain: "InvalidKeySize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid key size. Use 128-bit or 256-bit key."])
        }
        guard nonce.count == kCCBlockSizeAES128 else {
            throw NSError(domain: "InvalidNonceSize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid nonce size. Use 128-bit nonce."])
        }

        let n = try calcOMAC(key: key, prefix: 0, message: nonce)
        let h = try calcOMAC(key: key, prefix: 1, message: associatedData)
        let c = try calcOMAC(key: key, prefix: 2, message: ciphertext)

        let tagToVerify = xorWithPadding(data1: xorWithPadding(data1: n, data2: h), data2: c).prefix(tag.count)

        if tagToVerify != tag {
            throw NSError(domain: "InvalidTag", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid tag!"])
        }

        // Decrypt the ciphertext using AES-CTR
        return try AESCTR.decrypt(key: key, nonce: n, data: ciphertext)
    }

    fileprivate static func xorWithPadding(data1: Data, data2: Data) -> Data {
        // Get max length
        let maxLength = max(data1.count, data2.count)

        // Zero-pad shorter data objects to match the maximum length
        let paddedData1 = data1 + Data(repeating: 0, count: maxLength - data1.count)
        let paddedData2 = data2 + Data(repeating: 0, count: maxLength - data2.count)

        // Perform XOR operation
        let xorResult = zip(paddedData1, paddedData2).map { $0 ^ $1 }

        // Return the result as Data
        return Data(xorResult)
    }

    fileprivate static func getOmacPrefix(index: UInt8) throws -> Data {
        // 16-byte prefix for OMAC
        var data = Data(repeating: 0, count: 16)

        if let lastIndex = data.indices.last {
            data[lastIndex] = index
            return data
        }

        throw NSError(domain: "InvalidIndex", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid index!"])
    }

    fileprivate static func calcOMAC(key: Data, prefix: UInt8, message: Data) throws -> Data {
        try calcCMAC(key: key, message: getOmacPrefix(index: prefix) + message)
    }

    fileprivate static func calcCMAC(key: Data, message: Data) throws -> Data {
        let cmac = try CMAC(key: key.bytes)
        let mac = try cmac.authenticate(message.bytes)
        return Data(mac)
    }
}

/// Data extension to get bytes from data
private extension Data {
    var mutableBytes: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(mutating: (self as NSData).bytes)
    }
}
