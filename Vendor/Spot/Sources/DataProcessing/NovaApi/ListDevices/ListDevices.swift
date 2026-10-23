//
//  ListDevices.swift
//  Spot
//
//  Created by Leon Böttger on 05.12.24.
//

import Foundation

class DeviceListRequest {
    let payload: Data

    init() {
        var wrapper = DevicesListRequest()

        // Query for Spot devices
        wrapper.deviceListRequestPayload.type = .spotDevice

        // Set a random UUID as the request ID
        wrapper.deviceListRequestPayload.id = getRandomUUID()

        // Serialize to binary data
        payload = try! wrapper.serializedData()
    }
}
