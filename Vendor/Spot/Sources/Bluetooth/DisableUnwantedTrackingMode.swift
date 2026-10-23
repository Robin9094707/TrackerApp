//
//  DisableUnwantedTrackingMode.swift
//
//
//  Created by Leon Böttger on 26.12.24.
//

import Foundation
import UIKit

class DisableUnwantedTrackingModeOperation {
    private static var bg = UIBackgroundTaskIdentifier.invalid
    private static var queuedDevices = [String]()
    private static let disableUnwantedTrackingModeQueue = DispatchQueue(label: "DisableUnwantedTrackingModeQueue")

    static func perform(device: LocalFindMyDevice, bluetoothId: String) {
        let canonicDeviceId = device.canonicDeviceId

        disableUnwantedTrackingModeQueue.sync {
            if queuedDevices.contains(canonicDeviceId) {
                return
            }

            guard let eik = device.eik else { return }

            startBackgroundTask()
            queuedDevices.append(canonicDeviceId)

            UploadOwnerScansRequest.uploadCurrentLocation(device: device) { _ in
                FMDNOwnerOperations.executeDisableUnwantedTrackingProtectionOperation(currentBluetoothId: bluetoothId, eik: eik) { _, _ in
                    disableUnwantedTrackingModeQueue.async {
                        queuedDevices.removeAll { $0 == canonicDeviceId }

                        if queuedDevices.isEmpty {
                            endBackgroundTask()
                        }
                    }
                }
            }
        }
    }

    private static func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(bg)
        bg = .invalid
    }

    private static func startBackgroundTask() {
        endBackgroundTask()
        bg = UIApplication.shared.beginBackgroundTask(expirationHandler: { () in
            endBackgroundTask()
        })
    }
}
