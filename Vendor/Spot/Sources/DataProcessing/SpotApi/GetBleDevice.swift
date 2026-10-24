//
//  GetBleDevice.swift
//  Spot
//
//  Created by Leon Böttger on 21.12.24.
//

import Foundation
import Combine

class GetBleDevice {
    static func perform(canonicDeviceId: String) async throws -> GetBleDeviceResponse {
        var requestProto = GetBleDeviceRequest()
        requestProto.device.id = canonicDeviceId

        let serializedProto = try requestProto.serializedData()

        let result = try await SpotApiManager.spotRequest(apiScope: "GetBleDevice", payload: serializedProto)

        return try GetBleDeviceResponse(serializedBytes: result)
    }
}
