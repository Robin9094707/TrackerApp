//
//  EIDGenerator.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import BigInt
import CommonCrypto
import CryptoKit
import Foundation
import Combine
import SwiftECC
import SwiftUI

class EIDGenerator {
    /// K = Rotation period exponent
    private static let K = 10

    static func getCurrentEID(for device: LocalFindMyDevice, secondsOffset: Int32 = 0) throws -> Data {
        guard let eik = device.eik else {
            throw NSError(domain: "EIDGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "EIK is nil"])
        }

        return try EIDGenerator.generateEID(identityKey: eik, timeOffset: device.beaconTimeCounter + secondsOffset, curveType: device.curveType)
    }

    static func generateEID(identityKey: Data, timeOffset: Int32, curveType: CurveType) throws -> Data {
        // Calculate r
        let r = try calculateR(identityKey: identityKey, timestamp: timeOffset, curveType: curveType)

        // Compute R = r * G (ECDH)
        let curve = curveType.curve
        let R = try curve.multiplyPoint(curve.g, r)

        // Return the x coordinate of R as the EID
        return ensureDataLength(R.x.data, length: curveType.length)
    }

    static func calculateR(identityKey: Data, timestamp: Int32, curveType: CurveType) throws -> BInt {
        // tsBytes is the timestamp in bytes, with the least K significant bits are set to 0
        let tsBytes = getMaskedTimestamp(timestamp: timestamp, K: 10)

        // Get the structured byte array
        var data = Data(count: 32)
        data.replaceSubrange(0 ..< 11, with: Data(repeating: 0xFF, count: 11))
        data[11] = UInt8(K)
        data.replaceSubrange(12 ..< 16, with: tsBytes)
        data.replaceSubrange(16 ..< 27, with: Data(repeating: 0x00, count: 11))
        data[27] = UInt8(K)
        data.replaceSubrange(28 ..< 32, with: tsBytes)

        // AES-ECB-256 encryption
        let rDash = try AESECB.encrypt(data: data, key: identityKey)

        // Convert r' to an integer
        let rDashInt = BInt(magnitude: Bytes(rDash))

        // SECP160R1 parameters
        let curve = curveType.curve
        let n = curve.order

        // r' is projected to the finite field Fp by calculating r = r' mod n
        return rDashInt % n
    }

    fileprivate static func getMaskedTimestamp(timestamp: Int32, K: Int) -> Data {
        // Create a bitmask that has all bits set except for the K least significant bits
        let mask: Int32 = ~((1 << K) - 1)

        // Zero out the K least significant bits
        let maskedTimestamp = timestamp & mask

        // Convert back to a byte array with the same length as the original
        var data = Data(count: 4)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: maskedTimestamp.bigEndian, as: Int32.self)
        }
        return data
    }
}

extension BInt {
    var data: Data {
        // Convert BInt to byte array
        let byteArray = asMagnitudeBytes()

        // Create Data object from byte array
        return Data(byteArray)
    }
}
