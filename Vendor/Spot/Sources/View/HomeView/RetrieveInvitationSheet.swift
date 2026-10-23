//
//  RetrieveInvitationSheet.swift
//  Spot
//
//  Created by Leon Böttger on 20.01.25.
//

import Foundation
import LUI
import SwiftUI

struct RetrieveInvitationSheet: View {
    @Binding var showSheet: Bool

    let invitation: SharingInvitation
    @State var loading = false
    @State var pin: String? = nil

    var body: some View {
        BottomBarView(header: "Invitation") {
            VStack {
                DeviceImageView(imageUrl: invitation.imageURL, size: 100)
                    .padding(.vertical, 20)

                LUIText(pin == nil ? "You have been invited to share \(invitation.deviceName) with \(invitation.ownerEmail)." : "You have accepted the invitation. Now, you need to wait until the owner accepts it.")
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                LUIText(pin == nil ? "Do you want to accept this invitation?" : "Check if the PIN \(pin ?? "????") matches with the owner's PIN.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

        } bottomView: {
            if pin != nil {
                LUIButton {
                    showSheet = false
                } label: {
                    LUIText("Done", color: .blue)
                        .padding()
                }
            } else {
                LargeButton2(label: "Accept Invite", loading: loading) {
                    Task {
                        loading = true
                        do {
                            pin = try await UpdateBleDeviceSharingSettings.acceptInvitation(invitation: invitation)

                            refreshDeviceList()
                        } catch {
                            showAlert(title: "Error", message: "Could not accept invitation.")
                        }

                        loading = false
                    }
                }
            }
        }
    }
}
