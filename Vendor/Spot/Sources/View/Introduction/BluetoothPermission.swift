//
//  BluetoothPermission.swift
//  Spot
//
//  Created by Leon Böttger on 24.03.25.
//

import LUI
import SwiftUI

struct BluetoothPermissionView: View {
    @ObservedObject var bluetoothManager = BluetoothManager.sharedInstance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let canProceed = bluetoothManager.centralManager?.state == .poweredOn || bluetoothManager.centralManager?.state == .poweredOff

        PermissionView(title: "Bluetooth-Zugriff", symbol: "magnifyingglass", subtitle: "Erlaube Bluetooth, damit RJ Tracker deine Google-Tracker in der Nähe finden und klingeln lassen kann.", permissionAction: {
            bluetoothManager.startCentralManager()

            if bluetoothManager.centralManager?.state == .unauthorized {
                openAppSettings()
            }

            if isSimulator() || canProceed {
                IntroductionViewController.sharedInstance.canProceed = true
            }

        }, continueLabel: "Weiter", canSkip: true, animateMockup: false) {
            LocationPermissionView()
        } nextViewSkip: {
            FirebaseRegisterView()
        } frontMockup: {
            AppMockupFrontView()
        } backMockup: {
            SymbolMockupView(symbol: "sensor.tag.radiowaves.forward.fill")
        }
        .onChange(of: canProceed) { _ in
            IntroductionViewController.sharedInstance.canProceed = true
        }
    }
}

func openAppSettings() {
    if let appSettings = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(appSettings) {
        UIApplication.shared.open(appSettings)
    }
}
