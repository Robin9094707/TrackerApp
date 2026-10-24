//
//  LocationCryptor.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import BigInt
import CryptoKit
import Foundation
import Combine
import SwiftECC
import SwiftUI

class LocationCryptor {
    private static let locationFetchQueue = DispatchQueue(label: "LocationFetchQueue")

    static func decryptList(device: LocalFindMyDevice, refresh: RefreshWrapper, completion: @escaping (RefreshWrapper) -> Void) {
        locationFetchQueue.async {

            guard let eik = device.eik else { completion(refresh); return }

            var modifiedRefresh = refresh

            for reportIndex in modifiedRefresh.reports.indices {
                do {
                    let report = modifiedRefresh.reports[reportIndex]

                    if report.decryptedLocation == nil {
                        let decryptedLocation = try LocationCryptor.decrypt(report: report, identityKey: eik, curveType: device.curveType, isCustomTracker: device.isCustomTracker)
                        modifiedRefresh.reports[reportIndex] = decryptedLocation

                        DispatchQueue.main.async {
                            if let refreshIndex = device.refreshes.firstIndex(where: { $0.id == refresh.id }) {
                                device.refreshes[refreshIndex] = modifiedRefresh
                            }
                        }
                    }
                } catch {
                    // Keep encrypted reports for key recovery; one failed report must not discard its neighbours.
                }
            }

            completion(modifiedRefresh)
        }
    }

    static func decrypt(report: LocationReportWrapper, identityKey: Data, curveType: CurveType, isCustomTracker: Bool) throws -> LocationReportWrapper {
        guard let encryptedLocation = report.encryptedLocation else {
            return report
        }

        let encryptedReport = encryptedLocation.encryptedReport
        let ephemeralPublicKey = encryptedReport.ephemeralPublicKey

        var decryptedLocation: DecryptedLocation

        if !ephemeralPublicKey.isEmpty {
            // Own ESP32-based tracker only use the first advertisement
            let offset = isCustomTracker ? 0 : encryptedLocation.deviceTimeOffset

            decryptedLocation = try LocationCryptor.decryptAsymmetric(identityKey: identityKey, encryptedAndTag: encryptedLocation.encryptedReport.encryptedLocation, Sx: ephemeralPublicKey, beaconTimeCounter: offset, curveType: curveType)
        } else {
            decryptedLocation = try LocationCryptor.decryptSymmetric(identityKey: identityKey, encryptedAndTag: encryptedLocation.encryptedReport.encryptedLocation)
        }

        var modifiedReport = report
        modifiedReport.decryptedLocation = decryptedLocation

        return modifiedReport
    }

    static func decryptAsymmetric(identityKey: Data, encryptedAndTag: Data, Sx: Data, beaconTimeCounter: Int32, curveType: CurveType) throws -> DecryptedLocation {
        do {
            let locationProtoBytes = try decryptAsymmetricToBytes(identityKey: identityKey, encryptedAndTag: encryptedAndTag, Sx: Sx, beaconTimeCounter: beaconTimeCounter, curveType: curveType)
            return try decryptedBytesToLocation(locationProtoBytes: locationProtoBytes)
        } catch {
            throw NSError(domain: "LocationCryptor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decrypt asymmetric location report at offset \(beaconTimeCounter). Error: \(error.localizedDescription)"])
        }
    }

    static func decryptSymmetric(identityKey: Data, encryptedAndTag: Data) throws -> DecryptedLocation {
        let hashedIdentityKey = SHA256.hash(data: identityKey)

        let locationProtoBytes = try AESGCM.decrypt(key: hashedIdentityKey, encryptedDataAndIV: encryptedAndTag)
        return try decryptedBytesToLocation(locationProtoBytes: locationProtoBytes)
    }

    static func encryptSymmetric(identityKey: Data, reportBytes: Data) throws -> Data {
        let hashedIdentityKey = SHA256.hash(data: identityKey)

        return try AESGCM.encrypt(key: hashedIdentityKey, plaintext: reportBytes)
    }

    private static func decryptedBytesToLocation(locationProtoBytes: Data) throws -> DecryptedLocation {
        let protoLocation = try Location(serializedBytes: locationProtoBytes)

        let latitude = Double(protoLocation.latitude) / 1e7
        let longitude = Double(protoLocation.longitude) / 1e7
        let altitude = Double(protoLocation.altitude)

        return DecryptedLocation(latitude: latitude, longitude: longitude, altitude: altitude)
    }

    static func encryptAsymmetricToBytes(message: Data, eid: Data, curveType: CurveType) throws -> (Data, Data) {
        if eid.count != curveType.length {
            throw NSError(domain: "InvalidEIDSize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid EID size. Use \(curveType.length)-byte EID."])
        }

        let random = try SecureRandom.getBytes(32)

        // Step 1: Choose a random number s in Fp
        let curve = curveType.curve
        let s = BInt(magnitude: Bytes(random))

        // Step 2: Compute S = s * G
        let S = try curve.multiplyPoint(curve.g, s)
        let Sx = S.x

        // Step 3: Compute R = (Rx, Ry) by substitution in the curve equation
        // and picking arbitrary Ry value out of possible results
        let Rx = BInt(magnitude: eid.bytes)
        let Ry = try rxToRy(Rx: Rx, curve: curve)
        let R = Point(Rx, Ry)

        // Step 4: Compute the 256-bit AES key k = HKDF-SHA256((s * R)x)
        // where (s * R)x is the x-coordinate of the curve multiplication.
        let sR = try curve.multiplyPoint(R, s)
        let hkdfSecret = SymmetricKey(data: ensureDataLength(Data(sR.x.asMagnitudeBytes()), length: curveType.length))
        let k = try HKDF.deriveKey(secret: hkdfSecret, salt: Data(), info: Data(), outputLength: 32)

        // Step 5: Split Rx and Sx into lower 8 bytes
        let LRx = Array(Rx.asMagnitudeBytes().suffix(8))
        let LSx = Array(Sx.asMagnitudeBytes().suffix(8))

        // Step 6: Compute nonce
        let nonce = LRx + LSx

        // Step 7: Encrypt the message m using AES-EAX-256
        let (mDash, tag) = try AESEAX.encrypt(key: k, nonce: Data(nonce), plaintext: message)

        // Step 8: Result (m' || tag, Sx)
        return (mDash + tag, Data(Sx.asMagnitudeBytes().prefix(curveType.length)))
    }

    static func decryptAsymmetricToBytes(identityKey: Data, encryptedAndTag: Data, Sx: Data, beaconTimeCounter: Int32, curveType: CurveType) throws -> Data {
        if identityKey.count != 32 {
            throw NSError(domain: "InvalidEIKSize", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid EIK size. Use 256-bit key."])
        }

        // Split into encrypted message and 16-byte tag
        let mDash = encryptedAndTag.prefix(encryptedAndTag.count - 16)
        let tag = encryptedAndTag.suffix(16)

        // Given the beacon time counter value on which URx is based, compute the value of r
        let curve = curveType.curve
        let r = try EIDGenerator.calculateR(identityKey: identityKey, timestamp: beaconTimeCounter, curveType: curveType)

        // Compute R = r * G
        let R = try curve.multiplyPoint(curve.g, r)

        // Compute S = (Sx, Sy) by substitution in the curve equation and picking an arbitrary Sy out of the results.
        let SxInt = BInt(magnitude: Sx.bytes)
        let SyInt = try rxToRy(Rx: SxInt, curve: curve)
        let S = Point(SxInt, SyInt)

        // Compute k = HKDF-SHA256((r * S)x) where (r * S)x is the x coordinate of the multiplication result.
        let rS = try curve.multiplyPoint(S, r)

        let hkdfSecret = SymmetricKey(data: ensureDataLength(Data(rS.x.asMagnitudeBytes()), length: curveType.length))
        let k = try HKDF.deriveKey(secret: hkdfSecret, salt: Data(), info: Data(), outputLength: 32)

        // Compute nonce = LRx || LSx.
        let LRx = Array(R.x.asMagnitudeBytes().suffix(8))
        let LSx = Array(S.x.asMagnitudeBytes().suffix(8))
        let nonce = LRx + LSx

        // Compute m = AES-EAX-256-DEC(k, nonce, m’, tag)
        return try AESEAX.decrypt(key: k, nonce: Data(nonce), ciphertext: mDash, tag: tag)
    }

    private static func rxToRy(Rx: BInt, curve: Domain) throws -> BInt {
        // Calculate y^2 = x^3 + ax + b (mod p)
        let Ryy = (Rx * Rx * Rx + curve.a * Rx + curve.b) % curve.p

        // Calculate modular square root
        let Ry = Ryy.expMod((curve.p + 1) / 4, curve.p)

        // Verify the result
        if Ry.expMod(BInt(2), curve.p) != Ryy {
            throw NSError(domain: "InvalidEID", code: 1, userInfo: [NSLocalizedDescriptionKey: "The provided EID isn't a valid E2EE public key."])
        }

        // Ensure y is even
        if Ry % 2 != 0 {
            return curve.p - Ry
        }

        return Ry
    }

    private struct EncryptedLocationAndTimes {
        var encryptedLocation: LocationReport
        var time: Time
    }
}

struct DecryptedLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}
