//
//  ContentView.swift
//
//
//  Created by Leon Böttger on 05.12.24.
//

import LUI
import SwiftUI

struct ContentView: View {
    var initialDeviceID: String? = nil
    @StateObject var eidUploader = UploadPrecomputedPublicKeyIds.sharedInstance
    @StateObject var bluetoothManager = BluetoothManager.sharedInstance
    @StateObject var tokenManager = TokenManager.sharedInstance
    @StateObject var locationManager = LocationManager.sharedInstance
    @StateObject var settings = Settings.sharedInstance
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AppRootView(phoneView: {
            DeviceListView(initialDeviceID: initialDeviceID)
        }, settingsView: {
            if let _ = PushReceiver.sharedInstance.getToken(), let username = tokenManager.username {
                CustomSection(footer: "Bei aktivierter Hintergrundsuche kann RJ Tracker deine eigenen Google-Tracker per Bluetooth erkennen. iOS bestimmt, wann Hintergrundaktivität möglich ist.") {
                    Toggle(isOn: $settings.backgroundScanning) {
                        SettingsLabel(imageName: "text.magnifyingglass", text: "Bluetooth-Hintergrundsuche", backgroundColor: .green)
                    }
                }

                CustomSection {
                    LUILink(destination: LocalGoogleImportView()) { SettingsLabel(imageName: "doc.badge.plus", text: "Google JSON lokal importieren", backgroundColor: .blue) }
                }

                CustomSection(header: "Account", footer: "Beim Abmelden bleiben deine lokalen Verläufe erhalten. Du kannst dich jederzeit erneut anmelden.") {
                    SettingsLabel(imageName: "person.fill", text: username)

                    LUIButton {
                        LUISettings.sharedInstance.appLaunchedBefore = false
                        LUISettings.sharedInstance.showSettings = false

                        runAfter(seconds: 0.5) {
                            BluetoothManager.sharedInstance.reset()
                            tokenManager.deleteTokens()
                            Settings.sharedInstance.devicesList = nil
                        }
                    } label: {
                        NavigationLinkLabel(imageName: "xmark", text: "Google lokal abmelden", backgroundColor: .red)
                    }
                }
            }
        }, firstIntroductionView: {
            BluetoothPermissionView()
        })
        .modifier(KeyRecoverySheetModifier(isPresented: $settings.showKeyRecoverySheet))
        .onChange(of: scenePhase) { newPhase in
            scenePhaseChanged(newPhase)
        }
        .onAppear {
            scenePhaseChanged(scenePhase)
        }
    }

    func scenePhaseChanged(_ newPhase: ScenePhase) {
        Settings.sharedInstance.isBackground = newPhase != .active
    }
}
