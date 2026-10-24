//
//  RegisterBleDeviceKeyGen.swift
//
//
//  Created by Leon Böttger on 19.12.24.
//

import Foundation
import Combine

let ROTATION_PERIOD: Int32 = 1024

class RegisterBleDeviceKeyGen {
    static func generateE2EEKeys(pairDate: Int32, curveType: CurveType, eidLimitSeconds: Int = 86400, isCustomTracker: Bool) throws -> E2EEKeys {
        let eik = try createEIK()
        let accountKey = try createAccountKey()
        let eids = try getNextEids(eik: eik, curveType: curveType, pairDate: pairDate, startDate: pairDate, durationSeconds: eidLimitSeconds, isCustomTracker: isCustomTracker)

        return E2EEKeys(eik: eik, accountKey: accountKey, eids: eids)
    }

    static func generateE2EEKeys(eik: Data, accountKey: Data, curveType: CurveType, pairDate: Int32, eidLimitSeconds: Int = 86400, isCustomTracker: Bool) throws -> E2EEKeys {
        let eids = try getNextEids(eik: eik, curveType: curveType, pairDate: pairDate, startDate: pairDate, durationSeconds: eidLimitSeconds, isCustomTracker: isCustomTracker)
        return E2EEKeys(eik: eik, accountKey: accountKey, eids: eids)
    }

    static func createEIK() throws -> Data {
        try SecureRandom.getBytes(32)
    }

    static func createAccountKey() throws -> Data {
        try Data([0x04]) + SecureRandom.getBytes(15)
    }

    static func getNextEids(eik: Data,
                            curveType: CurveType,
                            pairDate: Int32,
                            startDate: Int32,
                            durationSeconds: Int = 86400,
                            isCustomTracker: Bool) throws -> [E2EEKeys.EidAndTimestamp]
    {
        let durationSeconds = Int32(durationSeconds)
        let startOffset: Int32 = startDate - pairDate

        let lock = NSLock()
        var eids = [E2EEKeys.EidAndTimestamp]()

        let iterationOffsets = stride(from: startOffset - (startOffset % ROTATION_PERIOD),
                                      to: startOffset + durationSeconds,
                                      by: Int32.Stride(ROTATION_PERIOD)).map { $0 }

        // OperationQueue for better scheduling
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.processorCount // Optimal core usage

        for offset in iterationOffsets {
            queue.addOperation {
                do {
                    let eid = try EIDGenerator.generateEID(identityKey: eik, timeOffset: isCustomTracker ? 0 : offset, curveType: curveType)
                    let time = pairDate + offset

                    lock.lock()
                    eids.append(E2EEKeys.EidAndTimestamp(eid: eid, timestamp: time))
                    lock.unlock()
                } catch {}
            }
        }

        queue.waitUntilAllOperationsAreFinished()
        return eids.sorted { $0.timestamp < $1.timestamp } // Ensure correct order
    }

    static func getSha256AccountKeyPublicAddress(accountKey: Data) -> Data {
        // note this is not how its done in the actual implementation, but it doesnt matter since this key is not used anyway
        SHA256.hash(data: accountKey)
    }

    static func getRecoveryKey(eik: Data) -> Data {
        calculateTruncatedSHA256(identityKey: eik, operation: Data([0x01]))
    }

    static func getRingingKey(eik: Data) -> Data {
        calculateTruncatedSHA256(identityKey: eik, operation: Data([0x02]))
    }

    static func getUnwantedTrackingKey(eik: Data) -> Data {
        calculateTruncatedSHA256(identityKey: eik, operation: Data([0x03]))
    }

    static func calculateTruncatedSHA256(identityKey: Data, operation: Data) -> Data {
        let length = 8
        let toHash = identityKey + operation

        let sha256Hash = SHA256.hash(data: toHash)
        let truncatedHash = sha256Hash.prefix(length)

        return Data(truncatedHash)
    }

    struct E2EEKeys {
        init(eik: Data, accountKey: Data, eids: [EidAndTimestamp]) {
            self.eik = eik
            self.accountKey = accountKey
            sha256AccountKeyPublicAddress = getSha256AccountKeyPublicAddress(accountKey: accountKey)
            recoveryKey = getRecoveryKey(eik: eik)
            ringingKey = getRingingKey(eik: eik)
            unwantedTrackingKey = getUnwantedTrackingKey(eik: eik)
            self.eids = eids
        }

        let eik: Data
        let accountKey: Data
        let sha256AccountKeyPublicAddress: Data
        let recoveryKey: Data
        let ringingKey: Data
        let unwantedTrackingKey: Data
        var eids: [EidAndTimestamp]

        struct EidAndTimestamp: Equatable {
            let eid: Data
            let timestamp: Int32
        }
    }
}
