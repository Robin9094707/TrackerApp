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
                BigSymbolViewWithText(symbol: "plus.app.fill", subtitle: "Add new Find My Device trackers by asking someone to share their device with you, or by creating your own device.", title: "Add Device") {
                    VStack(spacing: luiModel.SettingsSectionSpacing) {
                        CustomSection {
                            LUILink(destination: AddInviteView(showSheet: $showAddDeviceSheet)) {
                                NavigationLinkLabel(imageName: "person.2.fill", text: "Add Shared Device", backgroundColor: .green)
                            }
                            LUILink(destination: ESPAddView(showSheet: $showAddDeviceSheet)) {
                                NavigationLinkLabel(imageName: "plus", text: "Create Own Device", backgroundColor: .blue)
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
