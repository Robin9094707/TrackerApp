//
//  DeviceOnlyKeys.swift
//
//
//  Created by Leon Böttger on 06.12.24.
//

import Foundation
import LUI

enum DeviceOnlyKeys: String, RawRepresentable {
    // Default keys
    case fcmCredentials
    case username
    case aasToken
    case ownerKey
    case ownerKeyVersion
    case sharedKey

    case contributorType
    case backgroundScanning
    case uploadInterval
    case automaticallyDisableUnwantedTrackingMode
}
