//
//  ESPAddView.swift
//
//
//  Created by Leon Böttger on 03.02.25.
//

import LUI
import SwiftUI
import UIKit

public struct ESPAddView: View {
    @Binding var showSheet: Bool

    @State var registering = false
    @State var secrets: RegisterBleDeviceKeyGen.E2EEKeys? = nil
    @State var pairDate: Int32 = 0

    @State var fetchQueue = DispatchQueue(label: "com.spot.espaddview.fetchqueue")
    @State var copied = false
    @State var copiedOnce = false

    @State var curveType = CurveType.secp160r1

    public var body: some View {
        NavigationSubView {
            BigSymbolViewWithText(symbol: "cpu", subtitle: "Create an ESP32-based tracker by copying the identifier below, and flashing it to your ESP32. For help, see the link below.", title: "Create Device") {
                let firstAdvertisement = secrets?.eids.first?.eid.hex

                VStack {
                    LUIButton {
                        copied = true
                        copiedOnce = true
                        copyToClipboard(string: firstAdvertisement)

                        runAfter(seconds: 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack {
                            Text(copied ? "Copied to Clipboard" : (firstAdvertisement ?? "Loading..."))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)

                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.mainColor)
                        }
                        .padding(20)
                        .padding(.horizontal)
                        .background(Color.gray.opacity(0.1).cornerRadius(15))
                        .padding()
                    }
                    .animation(.easeInOut, value: copied)
                    .padding(.horizontal)
                    .padding(.top)

                    if let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex, let secrets {
                        ColoredButton(label: "Register Tracker", loading: registering) {
                            Task {
                                registering = true

                                do {
                                    let result = try await RegisterBleDevice.registerESP32(pairDate: pairDate, ownerKey: ownerKey, EIK: secrets.eik, curveType: curveType)

                                    showSheet = false
                                    refreshDeviceList()

                                    showAlert(title: "Success", message: "Your ESP32 has been registered successfully.")
                                } catch {}

                                registering = false
                            }
                        }
                        .padding(.top)
                        .opacity(copiedOnce ? 1 : 0.5)
                        .animation(.easeInOut, value: copiedOnce)
                    }

                    Spacer()

                    if let url = URL(string: "https://github.com/leonboe1/GoogleFindMyTools/blob/main/ESP32Firmware/README.md") {
                        LUIButton(action: {
                            openURL(url: url)
                        }, label: {
                            UnderlineText(label: "Instructions & Download Firmware")
                        })
                    }
                }
                .animation(.easeInOut, value: secrets == nil)
            }
        }
        .onAppear {
            fetchQueue.async {
                do {
                    let pairDate = Date().unixTime - Int32(minutesToSeconds(minutes: 10))
                    let secrets = try RegisterBleDeviceKeyGen.generateE2EEKeys(pairDate: pairDate, curveType: curveType, eidLimitSeconds: 1, isCustomTracker: true)

                    DispatchQueue.main.async {
                        self.pairDate = pairDate
                        self.secrets = secrets
                    }
                } catch {}
            }
        }
    }
}

private func copyToClipboard(string: String?) {
    #if !os(macOS)
        if let string {
            doubleVibration()
            let pasteboard = UIPasteboard.general
            pasteboard.string = string
        }
    #endif
}
