//
//  LocationPermission.swift
//  Spot
//
//  Created by Leon Böttger on 24.03.25.
//

import LUI
import SwiftUI

struct LocationPermissionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var locationManager = LocationManager.sharedInstance

    var body: some View {
        let canProceed = locationManager.permissionSet

        PermissionView(title: "Dein Standort", symbol: "mappin.and.ellipse", subtitle: "Mit deinem Standort kann RJ Tracker Sichtungsmeldungen für deine eigenen Tracker in der Nähe aktualisieren.", permissionAction: {
            let authorizationStatus = locationManager.locationManager?.authorizationStatus ?? .notDetermined
            let authorizationAccuracy = locationManager.locationManager?.accuracyAuthorization ?? .none

            if canProceed {
                IntroductionViewController.sharedInstance.canProceed = true
            }
            if authorizationStatus == .notDetermined {
                locationManager.requestWhenInUse()
            } else if locationManager.locationManager?.authorizationStatus == .denied || locationManager.locationManager?.authorizationStatus == .restricted {
                openAppSettings()
            }

            if authorizationStatus == .authorizedWhenInUse, authorizationAccuracy != .fullAccuracy {
                openAppSettings()
            }

        }, continueLabel: "Weiter", canSkip: true, animateMockup: false) {
            LocationAlwaysPermissionView()
        } nextViewSkip: {
            FirebaseRegisterView()
        } frontMockup: {
            AppMockupFrontView()
        } backMockup: {
            SymbolMockupView(symbol: "map.fill")
        }
        .onChange(of: canProceed) { _ in
            IntroductionViewController.sharedInstance.canProceed = true
        }
    }
}
