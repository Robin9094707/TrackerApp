//
//  TruncatedEidCache.swift
//  Spot
//
//  Created by Leon Böttger on 26.12.24.
//

import Foundation
import Combine

struct TruncatedEidInfo {
    let canonicDeviceId: String
    let timestamp: Int32
    let truncatedEid: Data
}

final class TruncatedEidCache: SharedInstance {
    static let sharedInstance = TruncatedEidCache()

    private init() {}

    private var cache: [Data: TruncatedEidInfo] = [:]
    private var ids: [String: [TruncatedEidInfo]] = [:]
    let cacheQueue = DispatchQueue(label: "com.leonboettger.spot.truncatedeidqueue")

    func lookup(truncatedEid: Data) -> TruncatedEidInfo? {
        cacheQueue.sync {
            cache[truncatedEid]
        }
    }

    func lookup(canonicDeviceId: String) -> [TruncatedEidInfo] {
        cacheQueue.sync {
            ids[canonicDeviceId] ?? []
        }
    }

    func process(canonicDeviceId: String, list: [PublicKeyIdList.PublicKeyIdInfo]) {
        cacheQueue.sync {

            if ids[canonicDeviceId] == nil {
                ids[canonicDeviceId] = [TruncatedEidInfo]()
            }

            for item in list {
                let truncatedEid = item.publicKeyID.truncatedEid
                let timestamp = item.timestamp.seconds

                let info = TruncatedEidInfo(canonicDeviceId: canonicDeviceId, timestamp: timestamp, truncatedEid: truncatedEid)

                cache[truncatedEid] = info

                if let array = ids[canonicDeviceId], !array.contains(where: { $0.timestamp == timestamp }) {
                    ids[canonicDeviceId]?.append(info)
                }
            }
        }
    }
}
