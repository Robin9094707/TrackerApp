//
//  LUISettings.swift
//
//
//  Created by Leon Böttger on 06.08.23.
//

import SwiftUI

private enum DeviceOnlyKeys: String { case appLaunchedBefore }
public final class LUISettings: SharedInstance {
    public static let sharedInstance = LUISettings()
    @SyncStorage(
        key: DeviceOnlyKeys.appLaunchedBefore, defaultValue: false, on: LUISettings.self, ud: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!
    )
    public var appLaunchedBefore: Bool {
        didSet { if !appLaunchedBefore { canShowIntroductionSheet = true } }
    }

    @Published var canShowIntroductionSheet = true
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published public var showSettings = false
}

public func showAlert(title: String, message: String) {
    runAfter(seconds: 0) {
        LUISettings.sharedInstance.alertTitle = title
        LUISettings.sharedInstance.alertMessage = message
        LUISettings.sharedInstance.showAlert = true
    }
}
