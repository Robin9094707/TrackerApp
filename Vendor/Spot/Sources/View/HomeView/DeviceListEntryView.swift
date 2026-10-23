//
//  DeviceListEntryView.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import LUI
import SwiftUI

struct DeviceListEntryView: View {
    @ObservedObject var device: LocalFindMyDevice
    @ObservedObject var clock = Clock.sharedInstance

    var body: some View {
        LUILink(destination: DeviceDetailView(device: device)) {
            HStack {
                DeviceImageView(imageUrl: device.imageURL)

                HStack {
                    LUIText(getDeviceDescription())
                        .lineLimit(2)

                    HStack {
                        if device.sharingSettings.sharingState != .NotShared {
                            Image(systemName: "person.2.fill")
                        }

                        if device.isLost {
                            Image(systemName: "lock.fill")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.mainColor)
                    .opacity(0.5)

                    if let peripheral = device.bluetoothData, !deviceNotCurrentlyReachable(device: peripheral, currentDate: clock.currentDate) {
                        HStack {
                            Spacer()
                            LUIText("Nearby")
                                .opacity(0.6)
                        }
                        .transition(AnyTransition.opacity.animation(.easeInOut))
                    }
                }

                Spacer()

                ArrowRightView()
            }
            .contentShape(Rectangle())
        }
    }

    func getDeviceDescription() -> String {
        device.userDefinedName
    }
}

struct DeviceImageView: View {
    let imageUrl: String
    var size: CGFloat = 45

    var body: some View {
        ZStack {
            if let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.image?
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity.animation(.easeInOut))
                }
            }
        }
        .frame(width: size, height: size)
        .padding(.vertical, 10)
        .padding(.trailing, 8)
    }
}
