//
//  SoundRequest.swift
//  Spot
//
//  Created by Leon Böttger on 12.12.24.
//

import Foundation

class SoundRequest {
    static func create(action: SoundRequestAction, canonicDeviceId: String, gcmRegistrationId: String) throws -> Data {
        var actionRequest = NbeExecuteAction.create(canonicDeviceId: canonicDeviceId, gcmRegistrationId: gcmRegistrationId)

        if action == .start {
            actionRequest.action.startSound.component = .unspecified
        } else {
            actionRequest.action.stopSound.component = .unspecified
        }

        return try actionRequest.serializedData()
    }
}

enum SoundRequestAction {
    case start
    case stop
}
