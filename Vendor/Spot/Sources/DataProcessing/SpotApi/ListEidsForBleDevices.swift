//
//  ListEidsForBleDevices.swift
//  Spot
//
//  Created by Leon Böttger on 21.12.24.
//

import Foundation
import LUI
import SwiftUI

class ListEidsForBleDevices {
    static func perform() async throws -> ListEidsForBleDevicesResponse {
        let result = try await SpotApiManager.spotRequest(apiScope: "ListEidsForBleDevices", payload: Data())
        return try ListEidsForBleDevicesResponse(serializedBytes: result)
    }
}
