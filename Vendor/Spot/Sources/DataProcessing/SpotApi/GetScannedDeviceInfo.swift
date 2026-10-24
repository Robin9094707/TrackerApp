//
//  GetScannedDeviceInfo.swift
//
//
//  Created by Leon Böttger on 22.12.24.
//

import Foundation
import Combine
import SwiftUI

class GetScannedDeviceInfo {
    static func perform(eid: Data) async throws -> GetScannedDeviceInfoResponse? {
        var requestProto = GetScannedDeviceInfoRequest()
        requestProto.identifier.truncatedEid = TruncatedEID.fromEID(eid)
        let serializedProto = try requestProto.serializedData()

        let result = try await SpotApiManager.spotRequest(apiScope: "GetScannedDeviceInfo", payload: serializedProto)

        if result.count == 0 {
            return nil
        } else {
            return try GetScannedDeviceInfoResponse(serializedBytes: result)
        }
    }
}
