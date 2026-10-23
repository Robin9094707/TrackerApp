//
//  BluetoothManagerTimer.swift
//
//
//  Created by Leon Böttger on 25.05.22.
//

import Foundation

/// Timer to enable and disable scanning periodically to save power
class BluetoothManagerTimer: NSObject {
    /// The controlling timer instance
    var timer = Timer()

    /// The shared instance.
    static let sharedInstance = BluetoothManagerTimer()

    /// The initializer
    override private init() {
        super.init()

        // Start and stop scan every X seconds, but only if app is in foreground - required to refresh RSSI values without connecting to devices
        timer = Timer.scheduledTimer(withTimeInterval: Constants.scanInterval, repeats: true) { _ in
            if !Settings.sharedInstance.isBackground, BluetoothManager.sharedInstance.turnedOn, BluetoothManager.sharedInstance.rssiScanForDevice == nil {
                if BluetoothManager.sharedInstance.scanning {
                    BluetoothManager.sharedInstance.stopScan()
                    BluetoothManager.sharedInstance.startScan()
                }
            }
        }
    }
}
