//
//  NbeExecuteAction.swift
//  Spot
//
//  Created by Leon Böttger on 07.12.24.
//

import Foundation

class NbeExecuteAction {
    /// Generate a random, but fixed client ID for request identification for this session
    static let clientId = UUID().uuidString

    static func create(canonicDeviceId: String, gcmRegistrationId: String, requestUuid: String = getRandomUUID(), fmdClientUuid: String = clientId) -> ExecuteActionRequest {
        var actionRequest = ExecuteActionRequest()

        var canonicId = CanonicId()
        canonicId.id = canonicDeviceId

        actionRequest.requestMetadata.type = .spotDevice
        actionRequest.requestMetadata.requestUuid = requestUuid
        actionRequest.requestMetadata.fmdClientUuid = fmdClientUuid
        actionRequest.requestMetadata.unknown = true
        actionRequest.requestMetadata.gcmRegistrationID.id = gcmRegistrationId
        actionRequest.scope.type = .spotDevice
        actionRequest.scope.device.canonicID = [canonicId]

        return actionRequest
    }
}
