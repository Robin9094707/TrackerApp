//
//  FirebaseRegister.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import LUI
import SwiftUI

struct FirebaseRegisterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var finished = false
    @State private var failed = false

    var body: some View {
        PermissionView(title: "Setup", symbol: "icloud", subtitle: "Deine lokale Google-Verbindung wird eingerichtet. Bitte prüfe, dass du mit dem Internet verbunden bist.", continueLabel: "", canSkip: false, animateMockup: true) {
            IntroductionDoneView()
        } nextViewSkip: {
            IntroductionDoneView()
        } frontMockup: {
            AppMockupFrontView()
        } backMockup: {
            SymbolMockupView(symbol: "globe")
        }
        .onAppear { prepare() }
        .overlay(alignment: .bottom) {
            if failed {
                Button("Erneut verbinden") { prepare() }.buttonStyle(.borderedProminent).padding(.bottom, 50)
            }
        }
        .modifier(LinkTo(content: { GoogleEmailView() }, isActive: $finished))
    }
    private func prepare() {
        failed = false
        PushReceiver.sharedInstance.registerForLogin {
            if PushReceiver.sharedInstance.getToken() != nil { finished = true }
            else { failed = true }
        }
    }
}
