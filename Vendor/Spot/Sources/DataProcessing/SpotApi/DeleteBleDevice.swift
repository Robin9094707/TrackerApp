//
//  DeleteBleDevice.swift
//  Spot
//
//  Created by Leon Böttger on 17.12.24.
//

import Foundation
import Combine

class DeleteBleDevice {
    static func perform(canonicDeviceId: String) async throws {
        var requestProto = DeleteBleDeviceRequest()
        requestProto.deviceToBeDeleted.id = canonicDeviceId

        let serializedProto = try requestProto.serializedData()

        _ = try await SpotApiManager.spotRequest(apiScope: "DeleteBleDevice", payload: serializedProto)
    }
}
