//
//  UploadPrecomputedPublicKeyIds.swift
//
//
//  Created by Leon Böttger on 24.12.24.
//

import Foundation
import Combine
import SwiftUI

final class UploadPrecomputedPublicKeyIds: SharedInstance {
    static var sharedInstance = UploadPrecomputedPublicKeyIds()

    private init() {}

    @Published var isUploading = false

    var isChecking = false
    let eidUploadQueue = DispatchQueue(label: "EidUploadQueue")

    var timer: Timer?

    func checkAndUpload() throws {
        eidUploadQueue.async {
            if self.isChecking {
                return
            }

            self.isChecking = true

            Task {

                var uploadRequest = UploadPrecomputedPublicKeyIdsRequest()

                let cloudIds = try await ListEidsForBleDevices.perform()
                var needsToUpload = false

                let allDevices = try await NovaApiManager.sharedInstance.requestDeviceList()

                for metadata in allDevices.deviceMetadata {
                    let deviceInformation = getInformation(deviceMetadata: metadata)

                    let registration = deviceInformation.deviceRegistration
                    let canonicDeviceID = registration.canonicID.id

                    let cloudIdObj = cloudIds.deviceEids.first(where: { $0.canonicID.id == canonicDeviceID })
                    let serverList = cloudIdObj?.serverList.publicKeyIDInfo ?? []

                    TruncatedEidCache.sharedInstance.process(canonicDeviceId: canonicDeviceID, list: serverList)

                    var isRefreshNeeded = false
                    var previousDate: Date? = nil

                    if let lastEidDate = cloudIdObj?.serverList.publicKeyIDInfo.last?.timestamp {
                        let lastEidAsDate = unixTimeToDate(unixTime: lastEidDate.seconds)
                        let nextDate = lastEidAsDate.addingTimeInterval(TimeInterval(ROTATION_PERIOD))

                        // If next EID will expire in less than a day, we need to refresh
                        isRefreshNeeded = nextDate.isInPast || nextDate.timeIntervalSinceNow < daysToSeconds(days: 1)

                        previousDate = lastEidAsDate
                    } else {
                        // nothing in list
                        isRefreshNeeded = true
                    }

                    let deviceName = registration.deviceDescription.userDefinedName

                    if isRefreshNeeded {
                        do {
                            // Do not sync Uber Trackers, not supported yet
                            if !deviceName.contains("UberTracker"), !deviceName.contains("SAT"), uploadRequest.deviceEids.count < 40 {
                                let isCustomTracker = registration.fastPairModelID == esp32Id

                                needsToUpload = true

                                DispatchQueue.main.async {
                                    withAnimation(.spring) {
                                        UploadPrecomputedPublicKeyIds.sharedInstance.isUploading = true
                                    }
                                }

                                let decryptedEik = try EIKDecryptor.decryptUsingDeviceRegistration(deviceRegistration: registration)

                                // start with 3 hours past current date, just like in Google's app
                                var firstEidDate = Date().addingTimeInterval(-hoursToSeconds(hours: 3))

                                // If previous date already includes last 3 hours, we dont need to re-upload those reports, so we start with the next one
                                if let previousDate, previousDate > firstEidDate {
                                    firstEidDate = previousDate.addingTimeInterval(TimeInterval(ROTATION_PERIOD))
                                }

                                // upload all EIDs for next 2 days
                                let eidSize = Int(daysToSeconds(days: 2))
                                let pairDate = registration.pairDate
                                let startDate = firstEidDate.unixTime

                                let eids = try RegisterBleDeviceKeyGen.getNextEids(eik: decryptedEik, curveType: registration.deviceEncryptionScheme == .eid20Bytes ? .secp160r1 : .secp256r1, pairDate: pairDate, startDate: startDate, durationSeconds: eidSize, isCustomTracker: isCustomTracker)

                                var protoPubKeyIdInfo = UploadPrecomputedPublicKeyIdsRequest.DevicePublicKeyIds()
                                protoPubKeyIdInfo.canonicID.id = canonicDeviceID

                                protoPubKeyIdInfo.pairDate = registration.pairDate

                                var protoPubKeyIdList = [PublicKeyIdList.PublicKeyIdInfo]()

                                for eid in eids {
                                    var keyInfo = PublicKeyIdList.PublicKeyIdInfo()
                                    keyInfo.publicKeyID.truncatedEid = TruncatedEID.fromEID(eid.eid)
                                    keyInfo.timestamp.seconds = eid.timestamp

                                    protoPubKeyIdList.append(keyInfo)
                                }

                                protoPubKeyIdInfo.clientList.publicKeyIDInfo = protoPubKeyIdList
                                uploadRequest.deviceEids.append(protoPubKeyIdInfo)

                                TruncatedEidCache.sharedInstance.process(canonicDeviceId: canonicDeviceID, list: protoPubKeyIdInfo.clientList.publicKeyIDInfo)
                            }
                        } catch {}
                    } else {}
                }

                if needsToUpload {
                    let serializedProto = try uploadRequest.serializedData()

                    do {
                        let result = try await SpotApiManager.spotRequest(apiScope: "UploadPrecomputedPublicKeyIds", payload: serializedProto)
                    } catch {}
                } else {}

                DispatchQueue.main.async {
                    withAnimation(.spring) {
                        UploadPrecomputedPublicKeyIds.sharedInstance.isUploading = false
                    }
                }

                self.isChecking = false
            }

            if self.timer == nil {
                self.timer = Timer.scheduledTimer(withTimeInterval: hoursToSeconds(hours: 12), repeats: true) { _ in
                    try? self.checkAndUpload()
                }
            }
        }
    }
}
