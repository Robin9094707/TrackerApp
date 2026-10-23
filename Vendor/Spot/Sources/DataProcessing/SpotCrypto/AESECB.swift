//
//  AESECB.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import CommonCrypto
import Foundation
import LUI
import SwiftUI

class AESECB {
    static func encrypt(data: Data, key: Data) throws -> Data {
        // Ensure key length is valid
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES192 || key.count == kCCKeySizeAES256 else {
            throw NSError(domain: "InvalidKeySize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid key size. Use 128-bit, 192-bit or 256-bit key."])
        }

        // Ensure data length is a multiple of the AES block size (16 bytes)
        guard data.count % kCCBlockSizeAES128 == 0 else {
            throw NSError(domain: "InvalidDataLength", code: 0, userInfo: [NSLocalizedDescriptionKey: "Data length must be a multiple of 16 bytes for ECB mode"])
        }

        // Allocate buffer for encrypted data
        let encryptedData = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer {
            encryptedData.deallocate()
        }

        // Perform AES encryption in ECB mode
        var numBytesEncrypted: size_t = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), // Operation: Encrypt
            CCAlgorithm(kCCAlgorithmAES), // Algorithm: AES
            CCOptions(kCCOptionECBMode), // Options: ECB mode, no padding
            key.bytes, // Key
            key.count, // Key length
            nil, // Initialization vector (not used in ECB mode)
            data.bytes, // Input data
            data.count, // Input data length
            encryptedData, // Output buffer
            data.count, // Output buffer length
            &numBytesEncrypted // Number of bytes encrypted
        )

        // Check status and return encrypted data
        guard status == kCCSuccess else {
            throw NSError(domain: "AES-ECB Encryption Failed", code: Int(status))
        }

        return Data(bytes: encryptedData, count: numBytesEncrypted)
    }

    static func decrypt(data: Data, key: Data) throws -> Data {
        let keyLength = key.count

        guard keyLength == kCCKeySizeAES128 ||
            keyLength == kCCKeySizeAES192 ||
            keyLength == kCCKeySizeAES256
        else {
            throw NSError(domain: "Invalid AES key size", code: -1)
        }

        let dataLength = data.count
        let cryptLength = dataLength + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)

        var numBytesDecrypted: size_t = 0

        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode + kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, keyLength,
                        nil,
                        dataBytes.baseAddress, dataLength,
                        cryptBytes.baseAddress, cryptLength,
                        &numBytesDecrypted
                    )
                }
            }
        }

        if cryptStatus == kCCSuccess {
            cryptData.removeSubrange(numBytesDecrypted ..< cryptData.count)
            return cryptData
        } else {
            throw NSError(domain: "AES-ECB Decryption Failed", code: Int(cryptStatus))
        }
    }
}
