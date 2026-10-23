//
//  Settings.swift
//
//
//  Created by Leon Böttger on 23.12.24.
//

import LUI
import SwiftUI

final class Settings: SharedInstance {
    static var sharedInstance = Settings()

    private init() {}

    @Published var isBackground = false {
        didSet {
            BluetoothManager.sharedInstance.startScan()
        }
    }

    @Published var devicesList: [LocalFindMyDevice]? = nil
    @Published var showKeyRecoverySheet: Bool = false

    @SyncStorage(key: DeviceOnlyKeys.backgroundScanning, defaultValue: true, on: Settings.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var backgroundScanning: Bool
    @SyncStorage(key: DeviceOnlyKeys.uploadInterval, defaultValue: -1, on: Settings.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var uploadInterval: Double
    @SyncStorage(key: DeviceOnlyKeys.automaticallyDisableUnwantedTrackingMode, defaultValue: true, on: Settings.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var automaticallyDisableUnwantedTrackingMode: Bool

    @SyncStorage(key: DeviceOnlyKeys.contributorType, defaultValue: ContributorType.Adaptive, on: Settings.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!) var contributorType: ContributorType
}
