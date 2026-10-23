//
//  GoogleEmail.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import LUI
import SwiftUI

struct GoogleEmailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAlert = false
    @State private var finished = false
    @State private var importing = false
    @ObservedObject var tokenManager = TokenManager.sharedInstance

    @State var canSkip = TokenManager.sharedInstance.aasToken != nil

    var body: some View {
        PermissionView(title: "Login", symbol: "person.fill", subtitle: "Melde dich direkt mit deinem Google-Konto an. Deine Zugangsdaten und Schlüssel bleiben auf diesem iPhone.", continueLabel: "Weiter", canSkip: false, animateMockup: false) {
            if canSkip {
                IntroductionDoneView()
            } else {
                GoogleLoginView()
            }

        } nextViewSkip: {
            GoogleLoginView()
        } frontMockup: {
            AppMockupFrontView()
        } backMockup: {
            SymbolMockupView(symbol: "person.crop.circle.fill.badge.plus")
        }
        .overlay(alignment: .topTrailing) {
            Button("JSON importieren") { importing = true }.padding()
        }
        .sheet(isPresented: $importing) { NavigationStack { LocalGoogleImportView() } }
    }
}
