//
//  GetEidInfo.swift
//
//
//  Created by Leon Böttger on 11.12.24.
//

import Foundation
import LUI
import SwiftProtobuf
import SwiftUI

class EidInfoProvider {
    static func get() async throws -> GetEidInfoForE2eeDevicesResponse {
        var eidInfoRequest = GetEidInfoForE2eeDevicesRequest()
        eidInfoRequest.ownerKeyVersion = -1
        eidInfoRequest.hasOwnerKeyVersion_p = true

        let serializedProto = try eidInfoRequest.serializedData()

        let data = try await SpotApiManager.spotRequest(apiScope: "GetEidInfoForE2eeDevices", payload: serializedProto)

        return try GetEidInfoForE2eeDevicesResponse(serializedBytes: data)
    }
}
