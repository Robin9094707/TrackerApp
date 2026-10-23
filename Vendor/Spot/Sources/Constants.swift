//
//  Constants.swift
//
//
//  Created by Leon Böttger on 03.05.22.
//

import Foundation
import SwiftUI

let esp32Id = "003200"

enum Constants {
    /// Manual scan will also show devices which were last seen during the last `manualScanBufferTime` seconds before the app was opened
    static let manualScanBufferTime: Double = 200

    /// In this interval, the manual scan will be restarted. This enables RSSI update.
    static let scanInterval: Double = 23

    /// Assumed worst RSSI. Used for signal indicator.
    static let worstRSSI: Double = -100

    /// Service used for FMDN actions
    static let FindMyDeviceService = "FEAA"

    /// Service used for Fast Pair actions
    static let FastPairService = "FE2C"

    /// Characteristic used for Fast Pair actions
    static let FastPairBeaconActionsCharacteristic = "FE2C1238-8366-4814-8EB0-01DE32100BEA"
}
