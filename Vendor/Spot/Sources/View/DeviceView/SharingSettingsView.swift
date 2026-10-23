//
//  SharingSettingsView.swift
//  Spot
//
//  Created by Leon Böttger on 25.01.25.
//

import Foundation
import LUI
import SwiftUI

struct SharingSettingView: View {
    @ObservedObject var device: LocalFindMyDevice
    @State var removingAccount: String? = nil

    var body: some View {
        NavigationSubView(header: "Sharing") {
            CustomSection {
                ShareButton(label: "Share Device") {
                    try await UpdateBleDeviceSharingSettings.createSharingLink(device: device)
                }
            }
            .onAppear {
                // reload shared accounts if the view is opened
                refreshDeviceList()
            }

            if device.sharingSettings.usersWithAccess.count > 0 {
                CustomSection(header: "Users with Access") {
                    ForEach(device.sharingSettings.usersWithAccess, id: \.self) { sharedWith in
                        HStack {
                            LUIButton {
                                Task {
                                    withAnimation {
                                        removingAccount = sharedWith
                                    }

                                    do {
                                        try await UpdateBleDeviceSharingSettings.stopSharing(canonicDeviceID: device.canonicDeviceId, removedAccount: sharedWith)

                                        var newSharingSettings = device.sharingSettings
                                        newSharingSettings.usersWithAccess.removeAll { $0 == sharedWith }

                                        withAnimation(.smooth) {
                                            device.sharingSettings = newSharingSettings
                                        }
                                    } catch {
                                        showAlert(title: "Error", message: "Could not remove user. Please try again later.")

                                        withAnimation {
                                            removingAccount = nil
                                        }
                                    }
                                }
                            } label: {
                                SettingsIcon(imageName: "minus", backgroundColor: .red)
                            }

                            LUIText(sharedWith)

                            Spacer()

                            LoadingIndicator()
                                .opacity(removingAccount == sharedWith ? 0.8 : 0)
                                .frame(width: 20)
                        }
                        .frame(height: luiModel.SettingsLabelHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
