//
//  AddDeviceView.swift
//
//
//  Created by Leon Böttger on 01.02.25.
//

import LUI
import SwiftUI
import WebKit

struct AddDeviceView: View {
    @Binding var showAddDeviceSheet: Bool
    let refresh: () -> Void

    var body: some View {
        NavigationView {
            NavigationSubView {
                BigSymbolViewWithText(symbol: "plus.app.fill", subtitle: "Füge eine Google-Freigabe hinzu oder erstelle einen eigenen ESP32-Tracker. Handelsübliche Tracker werden zuerst mit einem kompatiblen Android-Gerät gekoppelt.", title: "Tracker hinzufügen") {
                    VStack(spacing: luiModel.SettingsSectionSpacing) {
                        CustomSection {
                            LUILink(destination: AddInviteView(showSheet: $showAddDeviceSheet)) {
                                NavigationLinkLabel(imageName: "person.2.fill", text: "Geteilten Tracker hinzufügen", backgroundColor: .green)
                            }
                            LUILink(destination: ESPAddView(showSheet: $showAddDeviceSheet)) {
                                NavigationLinkLabel(imageName: "plus", text: "Eigenen Tracker erstellen", backgroundColor: .blue)
                            }
                        }

                        Spacer()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        showAddDeviceSheet = false
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }
}
