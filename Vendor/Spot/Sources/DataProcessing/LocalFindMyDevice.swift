//
//  LocalFindMyDevice.swift
//  Spot
//
//  Created by Leon Böttger on 23.12.24.
//

import Foundation
import Combine
import SwiftUI

private let deviceRefreshQueue = DispatchQueue(label: "DeviceRefreshQueue")

struct SharingSettings {
    var sharingState: SharingState
    var pendingShareOperations: [SharingOperation]
    var usersWithAccess: [String]

    struct SharingOperation {
        let accountName: String
        let sharingOwnPrivateKey: PrivateKeyWrapper?
        let sharingOtherPublicKey: Data?
    }
}

class LocalFindMyDevice: ObservableObject, Identifiable, Equatable {
    static func == (lhs: LocalFindMyDevice, rhs: LocalFindMyDevice) -> Bool {
        lhs.canonicDeviceId == rhs.canonicDeviceId
    }

    init(canonicDeviceId: String,
         fastPairModelID: String,
         userDefinedName: String,
         manufacturer: String,
         model: String,
         deviceType: SpotDeviceType,
         isCustomTracker: Bool,
         imageURL: String,
         pairDate: Date,
         ownerKeyVersion: Int,
         keyDate: Date,
         eik: Data? = nil,
         accountKey: Data? = nil,
         encryptedKeys: EncryptedUserSecrets? = nil,
         serverRingingKey: Data? = nil,
         serverUnwantedTrackingKey: Data? = nil,
         curveType: CurveType,
         isLost: Bool,
         sharingSettings: SharingSettings,
         refreshes: [RefreshWrapper],
         lastReportUpload: Date?,
         lastReportRefresh: Date?)
    {
        self.canonicDeviceId = canonicDeviceId
        self.fastPairModelID = fastPairModelID
        self.userDefinedName = userDefinedName
        self.manufacturer = manufacturer
        self.model = model
        self.deviceType = deviceType
        self.isCustomTracker = isCustomTracker
        self.imageURL = imageURL
        self.pairDate = pairDate
        self.ownerKeyVersion = ownerKeyVersion
        self.keyDate = keyDate
        self.eik = eik
        self.accountKey = accountKey
        self.encryptedKeys = encryptedKeys
        self.serverRingingKey = serverRingingKey
        self.serverUnwantedTrackingKey = serverUnwantedTrackingKey
        self.isLost = isLost
        self.sharingSettings = sharingSettings
        self.refreshes = refreshes
        self.lastReportUpload = lastReportUpload
        self.lastReportRefresh = lastReportRefresh
        self.curveType = curveType
    }

    let accountName = TokenManager.sharedInstance.username?.lowercased()
    var belongsToCurrentAccount: Bool { accountName == TokenManager.sharedInstance.username?.lowercased() }
    let canonicDeviceId: String
    let fastPairModelID: String
    @Published var imageURL: String
    let pairDate: Date
    @Published var ownerKeyVersion: Int
    let keyDate: Date
    let manufacturer: String
    let model: String
    let curveType: CurveType
    let deviceType: SpotDeviceType
    var isCustomTracker: Bool

    var serverRingingKey: Data?
    var serverUnwantedTrackingKey: Data?

    @Published var sharingSettings: SharingSettings
    @Published var userDefinedName: String
    @Published var isLost: Bool
    @Published var batteryState: BatteryState = .Unknown

    @Published var eik: Data?
    @Published var accountKey: Data?
    let encryptedKeys: EncryptedUserSecrets?

    var reportRevision = UUID()
    @Published var refreshes: [RefreshWrapper] { didSet { reportRevision = UUID() } }
    // One compactor per tracker. Revisions prevent a completed worker from
    // replacing a report that arrived while the worker was sorting its copy.
    var historyCompaction: Task<Void, Never>?
    @MainActor func appendHistory(_ refresh: RefreshWrapper) {
        guard belongsToCurrentAccount else { return }
        refreshes.insert(refresh, at: 0)
        guard historyCompaction == nil else { return }
        historyCompaction = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.historyCompaction = nil }
            while self.belongsToCurrentAccount && !Task.isCancelled {
                let revision = self.reportRevision
                let batches = self.refreshes
                let reports = await Task.detached(priority: .utility) {
                    uniqueGoogleReports(batches.flatMap(\.reports))
                }.value
                guard self.belongsToCurrentAccount, !Task.isCancelled else { return }
                if revision != self.reportRevision { await Task.yield(); continue }
                if let latest = batches.first {
                    var merged = RefreshWrapper(time: latest.time, contributorType: latest.contributorType, reports: reports)
                    merged.hasNewReport = batches.contains { $0.hasNewReport }
                    self.refreshes = [merged]
                }
                return
            }
        }
    }
    var lastReportUpload: Date?
    @Published var lastReportRefresh: Date?

    var id: String {
        canonicDeviceId
    }

    @Published var bluetoothData: BluetoothTempData? = nil

    var beaconTimeCounter: Int32 {
        let pairDate = pairDate.timeIntervalSince1970
        let currentDate = Date().timeIntervalSince1970
        let distance = currentDate - pairDate

        return Int32(distance)
    }

    func uploadLocationIfNecessary() {
        let uploadInterval = Settings.sharedInstance.uploadInterval
        guard uploadInterval > 0 else { return }

        var needsToReport = lastReportUpload == nil
        if !needsToReport, let lastReportUpload, lastReportUpload.isOlderThan(seconds: uploadInterval) {
            needsToReport = true
        }

        if needsToReport {
            UploadOwnerScansRequest.uploadCurrentLocation(device: self) { _ in }
        }
    }
}

func refreshDeviceList(finished: (() -> Void)? = nil) {
    deviceRefreshQueue.async {
        Task {
            do {
                let account = TokenManager.sharedInstance.username?.lowercased()
                let result = try await NovaApiManager.sharedInstance.requestDeviceList()
                guard account == TokenManager.sharedInstance.username?.lowercased() else { return }
                await processDeviceList(list: result.deviceMetadata)
            } catch {}

            DispatchQueue.main.async {
                finished?()
            }
        }
    }
}

func processDeviceList(list: [DeviceMetadata]) async {
    var newList = [LocalFindMyDevice]()

    let existingDevices = Settings.sharedInstance.devicesList ?? []

    for metadata in list {
        if let newDevice = convertToLocalFindMyDevice(deviceMetadata: metadata, existingDevices: existingDevices) {
            newList.append(newDevice)
        }
    }

    await MainActor.run {
        Settings.sharedInstance.devicesList = newList
    }
}

func getInformation(deviceMetadata: DeviceMetadata) -> DeviceMetadata.DeviceInformation {
    deviceMetadata.hasTrackerInformation ? deviceMetadata.trackerInformation : deviceMetadata.phoneInformation.information
}

func convertToLocalFindMyDevice(deviceMetadata: DeviceMetadata, existingDevices: [LocalFindMyDevice]) -> LocalFindMyDevice? {
    let deviceInformation = getInformation(deviceMetadata: deviceMetadata)
    let deviceRegistration = deviceInformation.deviceRegistration
    let accessInformation = deviceInformation.accessInformation

    if !deviceRegistration.hasCanonicID {
        return nil
    }

    let canonicId = deviceRegistration.canonicID.id
    let deviceName = deviceRegistration.deviceDescription.userDefinedName

    var sharingState = getSharingState(from: accessInformation)

    var sharedWith: [SharingSettings.SharingOperation] = []
    let usersWithAccess = accessInformation.filter { $0.hasAccess_p && !$0.thisAccount }.map(\.email)

    let isCustomTracker = deviceRegistration.fastPairModelID == esp32Id

    if sharingState == .SharedWithMePending {
        let myEntry = accessInformation.first(where: { $0.thisAccount })

        if let encryptedInviteePrivateKey = myEntry?.sharingKeys.inviteeKey,
           let encryptedOwnerPublicKey = myEntry?.sharingKeys.inviterKey,
           let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex,
           let email = myEntry?.email
        {
            do {
                let sharingOwnPrivateKey = try PrivateKeyWrapper(serializedBytes: AESGCM.decrypt(key: ownerKey, encryptedDataAndIV: encryptedInviteePrivateKey))
                let sharingOtherPublicKey = try AESGCM.decrypt(key: ownerKey, encryptedDataAndIV: encryptedOwnerPublicKey)

                sharedWith.append(SharingSettings.SharingOperation(accountName: email, sharingOwnPrivateKey: sharingOwnPrivateKey, sharingOtherPublicKey: sharingOtherPublicKey))
            } catch {}
        }
    }

    if sharingState == .SharedWithOthersPending, let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex {
        for theirEntry in accessInformation.filter({ !$0.hasAccess_p && $0.hasSharingKeys }) {
            do {
                let sharingInviterPrivateKey = try PrivateKeyWrapper(serializedBytes: AESGCM.decrypt(key: ownerKey, encryptedDataAndIV: theirEntry.sharingKeys.inviterKey))
                let sharingOtherPublicKey = theirEntry.sharingKeys.inviteeKey
                let email = theirEntry.email

                sharedWith.append(SharingSettings.SharingOperation(accountName: email, sharingOwnPrivateKey: sharingInviterPrivateKey, sharingOtherPublicKey: sharingOtherPublicKey))
            } catch {}
        }
    }

    var eik: Data? = nil
    var accountKey: Data? = nil
    var ownerKeyVersion = Int(deviceRegistration.encryptedKeys.ownerKeyVersion)

    if let ownerKey = TokenManager.sharedInstance.ownerKey?.dataFromHex {
        let encryptedEIK = deviceRegistration.encryptedKeys.encryptedIdentityKey
        let encryptedAccountKey = deviceRegistration.encryptedKeys.encryptedAccountKey

        do {
            if deviceRegistration.encryptedKeys.encryptedWithSharedSecret, let ownPrivateKey = sharedWith.first?.sharingOwnPrivateKey, let ownerPublicKey = sharedWith.first?.sharingOtherPublicKey {
                let creationDate = deviceRegistration.encryptedKeys.creationDate

                let (sharedEIK, sharedAccountKey) = try UpdateBleDeviceSharingSettings.decryptEikAndAccountKeyFromSharedSecret(canonicDeviceID: canonicId, encryptedEIK: encryptedEIK, encryptedAccountKey: encryptedAccountKey, creationDate: creationDate, ownerDER: ownerPublicKey, inviteePrivateKeyWrapper: ownPrivateKey)

                eik = sharedEIK
                accountKey = sharedAccountKey
                ownerKeyVersion = TokenManager.sharedInstance.ownerKeyVersion

                // Successfully decrypted and shared, so hide Sharing UI
                sharingState = .SharedWithMe
            } else {
                if ownerKeyVersion != TokenManager.sharedInstance.ownerKeyVersion, sharingState != .SharedWithMePending {
                    showAlert(title: "An Error Occurred", message: "Owner key version mismatch for device \(deviceName). Expected: \(TokenManager.sharedInstance.ownerKeyVersion), got: \(ownerKeyVersion). Try logging out and sign in again.")
                }

                if !encryptedEIK.isEmpty {
                    eik = try EIKDecryptor.decrypt(ownerKey: ownerKey, encryptedEIK: encryptedEIK, isObfuscated: isCustomTracker)
                }

                if !encryptedAccountKey.isEmpty {
                    accountKey = try AccountKeyDecryptor.decrypt(ownerKey: ownerKey, encryptedAccountKey: encryptedAccountKey)
                }

                var lastCreationDate: Time? = nil

                for rotatedEIK in deviceRegistration.keyRotationInformation.rotatedEiks.sorted(by: { $0.creationDate.seconds < $1.creationDate.seconds }) {
                    if let previousEIK = eik {
                        let encryptedRotatedEIK = rotatedEIK.encryptedEik
                        let newEik = try EIKDecryptor.decrypt(ownerKey: SHA256.hash(data: previousEIK), encryptedEIK: encryptedRotatedEIK, isObfuscated: false)

                        eik = newEik
                        lastCreationDate = rotatedEIK.creationDate
                    }
                }

                // EIK was updated, upload re-encrypted EIK to server
                if let date = lastCreationDate, let eik, let accountKey {
                    Task {
                        do {
                            try await UpdateBleDevice.setEncryptedUserSecrets(canonicDeviceId: canonicId, EIK: eik, accountKey: accountKey, creationDate: date)
                        } catch {}
                    }
                }
            }
        } catch {}
    }

    if let existing = existingDevices.first(where: { $0.canonicDeviceId == canonicId }) {
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                existing.userDefinedName = deviceName
                existing.imageURL = deviceMetadata.imageInformation.imageURL
                existing.isLost = deviceRegistration.lostModeInformation.lostModeEnabled
                existing.sharingSettings = SharingSettings(sharingState: sharingState, pendingShareOperations: sharedWith, usersWithAccess: usersWithAccess)
                existing.ownerKeyVersion = ownerKeyVersion
                existing.eik = eik
                existing.accountKey = accountKey
            }
        }

        return existing
    } else {
        let refreshes = loadReportsFromDisk(for: canonicId)
        let lastReportUpload = refreshes.first?.reports.first(where: { $0.isOwnReport })?.time
        let lastReportRefresh = refreshes.first?.time
        let pairDate = deviceRegistration.pairDate.date

        return LocalFindMyDevice(canonicDeviceId: canonicId,
                                 fastPairModelID: deviceRegistration.fastPairModelID,
                                 userDefinedName: deviceName,
                                 manufacturer: deviceRegistration.manufacturer,
                                 model: deviceRegistration.model,
                                 deviceType: deviceInformation.deviceRegistration.deviceDescription.deviceType,
                                 isCustomTracker: isCustomTracker,
                                 imageURL: deviceMetadata.imageInformation.imageURL,
                                 pairDate: pairDate,
                                 ownerKeyVersion: ownerKeyVersion,
                                 keyDate: deviceRegistration.encryptedKeys.creationDate.seconds.date,
                                 eik: eik,
                                 accountKey: accountKey,
                                 encryptedKeys: deviceRegistration.encryptedKeys,
                                 serverRingingKey: deviceRegistration.ringKey,
                                 serverUnwantedTrackingKey: deviceRegistration.unwantedTrackingKey,
                                 curveType: deviceRegistration.deviceEncryptionScheme == .eid20Bytes ? .secp160r1 : .secp256r1,
                                 isLost: deviceRegistration.lostModeInformation.lostModeEnabled,
                                 sharingSettings: SharingSettings(sharingState: sharingState, pendingShareOperations: sharedWith, usersWithAccess: usersWithAccess),
                                 refreshes: refreshes,
                                 lastReportUpload: lastReportUpload,
                                 lastReportRefresh: lastReportRefresh)
    }
}

private func getSharingState(from accessInformation: [AccessInformation]) -> SharingState {
    let otherSharedPending = accessInformation.first(where: { $0.thisAccount == false && $0.isOwner == false && !$0.hasAccess_p })

    if otherSharedPending != nil {
        return .SharedWithOthersPending
    }

    let myEntry = accessInformation.first(where: { $0.thisAccount })
    let isSharedWithMe = !(myEntry?.isOwner ?? false)

    if let entry = myEntry, !entry.hasAccess_p {
        return .SharedWithMePending
    }

    let isSharedTracker = accessInformation.contains(where: { !$0.thisAccount && !$0.isOwner })

    if isSharedTracker, !isSharedWithMe {
        return .SharedWithOthers
    }

    if isSharedWithMe {
        return .SharedWithMe
    }

    return .NotShared
}

enum SharingState {
    case NotShared
    case SharedWithOthers
    case SharedWithOthersPending
    case SharedWithMe
    case SharedWithMePending
}

enum BatteryState: String {
    case Unknown
    case Normal
    case Low
    case Critical

    var image: String {
        switch self {
        case .Unknown:
            "questionmark.circle"
        case .Normal:
            "battery.100"
        case .Low:
            "battery.50"
        case .Critical:
            "battery.25"
        }
    }

    var color: Color {
        switch self {
        case .Unknown:
            .gray
        case .Normal:
            .green
        case .Low:
            .yellow
        case .Critical:
            .red
        }
    }
}
