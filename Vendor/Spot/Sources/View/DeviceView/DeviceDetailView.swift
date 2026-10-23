//
//  DeviceDetailView.swift
//
//
//  Created by Leon Böttger on 08.12.24.
//

import CoreBluetooth
import CoreLocation
import LUI
import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var device: LocalFindMyDevice
    @State var refreshing = false

    var body: some View {
        NavigationSubView(header: device.userDefinedName, refreshAction: fetchDeviceUpdate) {
            DeviceDetailLocationsView(device: device, refreshing: $refreshing) {
                fetchDeviceUpdate()
            }
        }
        .animation(.easeInOut, value: refreshing)
    }

    func fetchDeviceUpdate() {
        withAnimation {
            refreshing = true
        }

        if device.sharingSettings.sharingState != .SharedWithMePending {
            NovaApiManager.sharedInstance.requestLocationDataForDevice(device: device) { _ in
                withAnimation {
                    refreshing = false
                }
            }
        } else {
            refreshDeviceList {
                withAnimation {
                    refreshing = false
                }
            }
        }
    }
}

struct DeviceDetailLocationsView: View {
    @ObservedObject var device: LocalFindMyDevice
    @Binding var refreshing: Bool
    let requestRefresh: () -> Void

    @ObservedObject private var clock = Clock.sharedInstance
    @Environment(\.colorScheme) private var colorScheme
    @State var playsSound = false
    @State var soundRequested = false

    @ObservedObject var tokenManager = TokenManager.sharedInstance
    @ObservedObject var settings = Settings.sharedInstance
    // @State var initiateKeyRecoveryProcess = false

    @State var showDeleteDeviceActionSheet = false
    @State var deletingDevice = false

    @State var showDeleteFailedAlert = false

    @ObservedObject var bluetoothManager = BluetoothManager.sharedInstance
    @Environment(\.presentationMode) var presentationMode

    @State var showTextEditField = false
    @State var deviceName = ""
    @State var detailMapShown = false

    var body: some View {
        let recentReports = device.refreshes.first?.reports ?? []

        DetailMapView(detailMapShown: $detailMapShown, refreshes: device.refreshes)

        if tokenManager.sharedKey == nil {
            CustomSection(backgroundColor: .red) {
                LUIButton {
                    settings.showKeyRecoverySheet = true
                } label: {
                    VStack {
                        HStack {
                            LUIText("Decrypt Location Reports", isBold: true, color: .white)
                                .padding(.bottom, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 5)

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white)
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.trailing, 5)
                        }

                        LUIText("To see the location of this tracker, you need to enter your Android phone's passcode.", color: .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 5)
                            .opacity(0.8)
                    }
                    .padding(.vertical)
                    .contentShape(Rectangle())
                }
            }
        }

        if let otherPublicDER = device.sharingSettings.pendingShareOperations.first?.sharingOtherPublicKey, let ownPrivateProto = device.sharingSettings.pendingShareOperations.first?.sharingOwnPrivateKey, device.sharingSettings.sharingState == .SharedWithMePending {
            CustomSection(header: "Device Sharing") {
                LUIText("Device was shared with you. Waiting for owner approval...")
                    .padding(.vertical)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let pin = UpdateBleDeviceSharingSettings.calculatePIN(ownerPublicKeyDER: otherPublicDER, inviteePublicKeyDER: ownPrivateProto.publicKey)

                CustomPickerLabel(selection: pin, backgroundColor: .orange, description: "Confirmation PIN", imageName: "key.horizontal.fill", isLink: false)
            }
        }

        if let otherDER = device.sharingSettings.pendingShareOperations.first?.sharingOtherPublicKey,
           let ownDER = device.sharingSettings.pendingShareOperations.first?.sharingOwnPrivateKey,
           let theirName = device.sharingSettings.pendingShareOperations.first?.accountName,
           let eik = device.eik,
           let accountKey = device.accountKey,
           device.sharingSettings.sharingState == .SharedWithOthersPending
        {
            CustomSection(header: "Device Sharing") {
                LUIText("Device was shared with \(theirName). Approve?")
                    .padding(.vertical)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let pin = UpdateBleDeviceSharingSettings.calculatePIN(ownerPublicKeyDER: ownDER.publicKey, inviteePublicKeyDER: otherDER)

                SettingsLoadingLabelAsync(imageName: "checkmark", text: "Approve", backgroundColor: .green) {
                    try await UpdateBleDeviceSharingSettings.acceptInviteeAndUploadEncryptedKeys(canonicDeviceID: device.canonicDeviceId, EIK: eik, accountKey: accountKey, inviteeAccount: theirName, creationDate: device.keyDate, inviteeDER: otherDER, ownerPrivateKeyWrapper: ownDER)

                    showAlert(title: "Success", message: "Successfully approved sharing request.")
                    requestRefresh()
                }

                CustomPickerLabel(selection: pin, backgroundColor: .orange, description: "Confirmation PIN", imageName: "key.horizontal.fill", isLink: false)
            }
        }

        CustomSection(header: "General") {
            LUIButton {
                requestRefresh()
            } label: {
                HStack {
                    let requestTime = device.lastReportRefresh
                    let selection = requestTime != nil ? timeToRelativeTime(date: pastTime(date: requestTime!), currentDate: clock.currentDate) : "Never"

                    CustomPickerLabel(selection: selection, backgroundColor: .blue, description: "Last Update", imageName: "clock.fill", isLink: false)

                    ZStack {
                        if refreshing {
                            LoadingIndicator()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.mainColor)
                        }
                    }
                    .opacity(0.7)
                    .frame(width: 18)
                    .onChange(of: requestTime) { _ in
                        withAnimation {
                            refreshing = false
                        }
                    }
                }
            }

            if let peripheral = device.bluetoothData, !deviceNotCurrentlyReachable(device: peripheral, currentDate: clock.currentDate) {
                LUILink(destination: PrecisionFindingView(tracker: device, bluetoothData: peripheral)) {
                    CustomPickerLabel(selection: "Nearby", backgroundColor: .orange, description: "Locate Tracker", imageName: "smallcircle.fill.circle.fill")
                }

                if device.batteryState != .Unknown, !device.isCustomTracker {
                    CustomPickerLabel(selection: device.batteryState.rawValue, backgroundColor: device.batteryState.color, description: "Battery Level", imageName: device.batteryState.image, isLink: false)
                }
            } else {
                LUIButton {
                    toggleSoundPlayback()
                } label: {
                    HStack {
                        SettingsLabel(imageName: "waveform", text: playsSound ? "Stop Sound Request" : "Request Sound", backgroundColor: .red)

                        if soundRequested {
                            LoadingIndicator()
                                .frame(width: 18)
                        } else {
                            ArrowRightView()
                        }
                    }
                }
            }
        }

        if !recentReports.isEmpty || device.refreshes.count > 0 {
            LocationsSection(device: device, reports: recentReports, showLocationHistoryLink: true)
        }

        if device.sharingSettings.sharingState != .SharedWithMePending, device.deviceType != .deviceTypePhone {
            let isSharedWithMe = device.sharingSettings.sharingState == .SharedWithMe

            CustomSection(header: "Manage Device") {
                LUIButton {
                    deviceName = device.userDefinedName
                    showTextEditField = true
                } label: {
                    NavigationLinkLabel(imageName: "character.cursor.ibeam", text: "Change Name", backgroundColor: .indigo)
                }
                .alert("Change Device Name", isPresented: $showTextEditField) {
                    TextField("Name", text: $deviceName)

                    Button("Save") {
                        Task {
                            try await UpdateBleDevice.setDeviceInfo(canonicDeviceId: device.canonicDeviceId, userDefinedName: deviceName, imageURL: device.imageURL)

                            withAnimation {
                                device.userDefinedName = deviceName
                            }
                        }
                    }

                    Button("Cancel", role: .cancel) {}
                }

                SettingsLoadingLabelAsync(imageName: device.isLost ? "lock.open.fill" : "lock.fill", text: device.isLost ? "Disable Lost Mode" : "Enable Lost Mode", backgroundColor: .green) {
                    let newValue = !device.isLost

                    try await UpdateBleDevice.setLostMode(canonicDeviceId: device.canonicDeviceId, lostMode: newValue)

                    withAnimation {
                        device.isLost = newValue
                    }
                }

                if !isSharedWithMe {
                    LUILink(destination: SharingSettingView(device: device)) {
                        NavigationLinkLabel(imageName: "person.2.fill", text: "Sharing Settings", backgroundColor: .blue)
                    }
                }

                SettingsLoadingLabel(imageName: isSharedWithMe ? "door.left.hand.open" : "trash", text: isSharedWithMe ? "Stop Sharing Device" : "Delete Device", backgroundColor: .red, isLoading: deletingDevice) {
                    showDeleteDeviceActionSheet = true
                }
            }
            .actionSheet(isPresented: $showDeleteDeviceActionSheet) {
                ActionSheet(title: Text("Delete Device"), message: Text("Are you sure you want to delete this device?"), buttons: [
                    .destructive(Text("Delete"), action: {
                        deleteDevice(sharedWithMe: isSharedWithMe)
                    }),
                    .cancel(),
                ])
            }
            .background(Color.clear.alert(isPresented: $showDeleteFailedAlert, content: {
                Alert(title: Text("Couldn't Delete Device"), message: Text("The device is not nearby or did not respond. Delete anyway?"), primaryButton: .cancel(Text("Cancel"), action: {
                    deletingDevice = false
                }), secondaryButton: .destructive(Text("Delete Anyway"), action: {
                    forceDeleteDevice(sharedWithMe: isSharedWithMe)
                }))
            }))
        }
    }

    func deleteDevice(sharedWithMe: Bool) {
        deletingDevice = true

        if sharedWithMe {
            forceDeleteDevice(sharedWithMe: sharedWithMe)
            return
        }

        if let bluetoothData = device.bluetoothData, let eik = device.eik, let accountKey = device.accountKey {
            FMDNOwnerOperations.executeUnpairOperation(currentBluetoothId: bluetoothData.identifier_background, eik: eik, accountKey: accountKey) { state, _ in
                if state == .Success {
                    forceDeleteDevice(sharedWithMe: sharedWithMe)
                } else {
                    showDeleteFailedAlert = true
                }
            }
        } else {
            showDeleteFailedAlert = true
        }
    }

    func forceDeleteDevice(sharedWithMe: Bool) {
        Task {
            do {
                if sharedWithMe {
                    try await UpdateBleDeviceSharingSettings.stopSharing(canonicDeviceID: device.canonicDeviceId)
                } else {
                    try await DeleteBleDevice.perform(canonicDeviceId: device.canonicDeviceId)
                }
                unpairCompleted()
            } catch {
                showDeleteFailedAlert = true
            }
        }
    }

    func unpairCompleted() {
        deletingDevice = false

        runAfter(seconds: 0.1) {
            presentationMode.wrappedValue.dismiss()

            withAnimation(.spring) {
                Settings.sharedInstance.devicesList?.removeAll(where: { $0.canonicDeviceId == device.canonicDeviceId })
            }
        }
    }

    func toggleSoundPlayback() {
        withAnimation {
            soundRequested = true
        }

        Task {
            do {
                try await NovaApiManager.sharedInstance.controlSoundForDevice(canonicDeviceId: device.canonicDeviceId, action: playsSound ? .stop : .start)

                playsSound.toggle()
                doubleVibration()

                runAfter(seconds: 2 * 60) {
                    playsSound = false
                }
            } catch {
                showAlert(title: "Sound Playback Error", message: "Error playing sound on device. Please try again later.")
            }

            withAnimation {
                soundRequested = false
            }
        }
    }
}

struct LocationsSection: View {
    let device: LocalFindMyDevice
    let reports: [LocationReportWrapper]
    let showLocationHistoryLink: Bool

    @ObservedObject private var clock = Clock.sharedInstance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CustomSection(header: "Location Reports") {
            ForEach(reports) { report in
                let label = statusToString(report.status, semanticLocation: report.name, colorScheme: colorScheme)

                LUILink(destination: DetailLocationView(report: report)) {
                    CustomPickerLabel(selection: relativeDateOrStaticString(report.time, currentDate: clock.currentDate), backgroundColor: label.color, description: label.label, imageName: label.icon, isLink: true)
                }
            }

            if showLocationHistoryLink {
                let distinctLocationsCount = getMapAnnotations(refreshes: device.refreshes).count

                LUILink(destination: PreviousReportsView(device: device)) {
                    CustomPickerLabel(selection: distinctLocationsCount.description, backgroundColor: .blue, description: "Location History", imageName: "clock.arrow.trianglehead.counterclockwise.rotate.90", isLink: true)
                }
            }
        }
    }
}
