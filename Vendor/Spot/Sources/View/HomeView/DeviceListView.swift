//
//  DeviceListView.swift
//
//
//  Created by Leon Böttger on 09.12.24.
//

import LUI
import SwiftUI

struct DeviceListView: View {
    var initialDeviceID: String? = nil
    @State private var showInitialDevice = false
    @State private var openedInitialDevice = false
    @State private var showImport = false
    @StateObject var fcmReceiver = PushReceiver.sharedInstance

    @ObservedObject var eidUploader = UploadPrecomputedPublicKeyIds.sharedInstance
    @ObservedObject var tokenManager = TokenManager.sharedInstance
    @ObservedObject var settings = Settings.sharedInstance

    @State var refreshing = true
    @State var showAddDeviceSheet = false

    var body: some View {
        NavigationSubView(header: "Google Find Hub", refreshAction: refresh) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Deine Dinge. Direkt verbunden.", systemImage: "sensor.tag.radiowaves.forward.fill")
                    .font(.title3.bold())
                Text("Standorte, Klingeln und Freigaben – mit deinem Google-Konto direkt auf diesem iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 12)
            if let devicesList = settings.devicesList {
                if devicesList.isEmpty {
                    Spacer()

                    LUIText("No Find My Device compatible trackers were paired with your account. Add new trackers on a Find My Device compatible phone.", centered: true)
                        .padding(.horizontal, 40)
                        .padding(.vertical)

                    ColoredButton(label: "Refresh") {
                        refresh()
                    }

                    Spacer()
                } else {
                    CustomSection {
                        ForEach(devicesList) { device in
                            DeviceListEntryView(device: device)
                        }
                    }
                }
            } else {
                VStack {
                    Spacer()

                    if refreshing {
                        LoadingIndicator()
                            .frame(width: 23)
                    } else {
                        LUIText("Couldn't fetch devices. Check your internet connection.", centered: true)
                            .padding()

                        ColoredButton(label: "Try Again") {
                            refresh()
                        }
                    }

                    Spacer()
                }
                .onAppear {
                    refresh()
                }
            }
        }
        .modifier(LinkTo(content: {
            if let device = settings.devicesList?.first(where: { $0.id == initialDeviceID }) {
                DeviceDetailView(device: device)
            }
        }, isActive: $showInitialDevice))
        .onReceive(settings.$devicesList) { devices in
            if !openedInitialDevice, let id = initialDeviceID, devices?.contains(where: { $0.id == id }) == true {
                openedInitialDevice = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showInitialDevice = true }
            }
        }
        .luiSheet(isPresented: $showAddDeviceSheet, content: {
            AddDeviceView(showAddDeviceSheet: $showAddDeviceSheet, refresh: refresh)
        })
        .toolbar {
            if eidUploader.isUploading {
                ToolbarItem(placement: .topBarLeading) {
                    LoadingIndicator()
                        .frame(width: 22, height: 20)
                        .opacity(0.6)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Device", systemImage: "plus") {
                    if tokenManager.ownerKey == nil {
                        settings.showKeyRecoverySheet = true
                    } else {
                        showAddDeviceSheet = true
                    }
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gear") {
                    LUISettings.sharedInstance.showSettings = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .animation(.easeInOut, value: refreshing)
    }

    func refresh() {
        refreshing = true
        Task { @MainActor in
            await GoogleTrackerStore.shared.refresh()
            refreshing = false
            if let error = GoogleTrackerStore.shared.errorMessage {
                showAlert(title: "Google Find Hub", message: error)
            }
        }

        do {
            try UploadPrecomputedPublicKeyIds.sharedInstance.checkAndUpload()
        } catch {}
    }
}
