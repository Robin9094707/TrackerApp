//
//  LocationRequest.swift
//  Spot
//
//  Created by Leon Böttger on 07.12.24.
//

import Foundation
import Combine

class LocationRequest {
    let payload: Data

    init(canonicDeviceId: String, fcmRegistrationId: String, requestUUID: String, atAllAreas: Bool) {
        var actionRequest = NbeExecuteAction.create(canonicDeviceId: canonicDeviceId, gcmRegistrationId: fcmRegistrationId, requestUuid: requestUUID)

        actionRequest.action.locateTracker.lastHighTrafficEnablingTime.seconds = 1_732_120_060
        actionRequest.action.locateTracker.contributorType = atAllAreas ? .fmdnAllLocations : .fmdnHighTraffic

        do {
            try payload = actionRequest.serializedData()
        } catch {
            payload = Data()
        }
    }
}
