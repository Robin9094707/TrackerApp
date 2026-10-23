//
//  LocationAlwaysPermission.swift
//  Spot
//
//  Created by Leon Böttger on 24.03.25.
//

import LUI
import SwiftUI

struct LocationAlwaysPermissionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var locationManager = LocationManager.sharedInstance

    var body: some View {
        let canProceed = locationManager.locationManager?.authorizationStatus == .authorizedAlways

        PermissionView(title: "Suche im Hintergrund", symbol: "mappin.and.ellipse", subtitle: "Erlaube den Standort im Hintergrund, um Sichtungsmeldungen für deine eigenen Tracker zu aktualisieren, während die App im Hintergrund aktiv ist.", permissionAction: {
            if canProceed {
                locationManager.enableBackgroundLocationUpdate()
                IntroductionViewController.sharedInstance.canProceed = true
            } else if locationManager.locationManager?.authorizationStatus == .denied || locationManager.locationManager?.authorizationStatus == .restricted {
                openAppSettings()
            } else {
                locationManager.requestAlwaysUsage()

                /// If the user prevously selected "Allow once" for location, no dialogue will appear when requesting always usage. We detect if a dialogue is shown using the background property. If the dialogue is shown, the app is in background. If not, we open the app settings

                runAfter(seconds: 0.3) {
                    if !Settings.sharedInstance.isBackground {
                        openAppSettings()
                    }
                }
            }

        }, continueLabel: "Weiter", canSkip: true, animateMockup: false) {
            FirebaseRegisterView()
        } nextViewSkip: {
            FirebaseRegisterView()
        } frontMockup: {
            AppMockupFrontView()
        } backMockup: {
            SymbolMockupView(symbol: "map.fill")
        }
        .onChange(of: canProceed) { _ in
            locationManager.enableBackgroundLocationUpdate()
            IntroductionViewController.sharedInstance.canProceed = true
        }
    }
}
