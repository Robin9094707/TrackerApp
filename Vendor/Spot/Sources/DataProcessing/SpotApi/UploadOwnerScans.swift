//
//  UploadOwnerScans.swift
//
//
//  Created by Leon Böttger on 15.12.24.
//

import CoreLocation
import Foundation
import Combine
import UIKit

class UploadOwnerScansRequest {
    private static var queuedDevices = [String]()
    private static let uploadQueue = DispatchQueue(label: "UploadOwnerScansQueue")
    private static var bg = UIBackgroundTaskIdentifier.invalid

    private static func perform(identityKey: Data, canonicDeviceId: String, location: CLLocation, date: Date) async throws -> Data {
        let ownerReport = try OwnerReportGenerator.generate(identityKey: identityKey, canonicDeviceId: canonicDeviceId, location: location, date: date)
        let serializedPayload = try ownerReport.serializedData()
        let publicKey = try await GetServicePublicKey.get()
        let encryptedPayload = try ServerPublicKeyEncryptor.encrypt(googlePublicKey: publicKey, plaintext: serializedPayload)

        var resultProto = UploadScansRequest()
        resultProto.reportsEncryptedWithServerKey = encryptedPayload
        let resultProtoData = try resultProto.serializedData()

        return try await SpotApiManager.spotRequest(apiScope: "UploadOwnerScans", payload: resultProtoData)
    }

    static func uploadCurrentLocation(device: LocalFindMyDevice, callback: @escaping (Bool) -> Void) {
        let canonicDeviceId = device.canonicDeviceId
        let date = Date()

        uploadQueue.sync {
            if queuedDevices.contains(canonicDeviceId) {
                return
            }

            guard let eik = device.eik else {
                requestEnded(success: false, canonicDeviceId: canonicDeviceId, callback: callback)
                showAlert(title: "Error", message: "Device is not setup yet.")
                return
            }

            queuedDevices.append(canonicDeviceId)
            startBackgroundTask()
            retrieveLocationAndUpload(canonicDeviceId: canonicDeviceId, eik: eik, device: device, date: date, callback: callback)
        }
    }

    private static func retrieveLocationAndUpload(canonicDeviceId: String, eik: Data, device: LocalFindMyDevice, date: Date, callback: @escaping (Bool) -> Void) {
        LocationManager.sharedInstance.getNewLocation { location in
            guard let location else {
                showAlert(title: "Failed", message: "Could not get location.")
                requestEnded(success: false, canonicDeviceId: canonicDeviceId, callback: callback)
                return
            }

            uploadLocation(location: location, eik: eik, device: device, date: date, canonicDeviceId: canonicDeviceId, callback: callback)
        }
    }

    private static func uploadLocation(location: CLLocation, eik: Data, device: LocalFindMyDevice, date: Date, canonicDeviceId: String, callback: @escaping (Bool) -> Void) {
        Task {
            do {
                _ = try await perform(identityKey: eik, canonicDeviceId: canonicDeviceId, location: location, date: date)
                device.lastReportUpload = Date()
                requestEnded(success: true, canonicDeviceId: canonicDeviceId, callback: callback)
            } catch {
                showAlert(title: "Error", message: "Could not upload location.")
                requestEnded(success: false, canonicDeviceId: canonicDeviceId, callback: callback)
            }
        }
    }

    private static func requestEnded(success: Bool, canonicDeviceId: String, callback: @escaping (Bool) -> Void) {
        uploadQueue.async {
            queuedDevices.removeAll { $0 == canonicDeviceId }

            if queuedDevices.isEmpty {
                endBackgroundTask()
            }

            DispatchQueue.main.async {
                callback(success)
            }
        }
    }

    private static func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(bg)
        bg = .invalid
    }

    private static func startBackgroundTask() {
        endBackgroundTask()
        bg = UIApplication.shared.beginBackgroundTask(expirationHandler: { () in
            endBackgroundTask()
        })
    }
}

class OwnerReportGenerator {
    static func generate(identityKey: Data, canonicDeviceId: String, location: CLLocation, date: Date) throws -> LocationReportsUpload {
        var report = LocationReportsUpload.Report()
        report.time.seconds = date.unixTime

        var protobufLocation = Location()
        protobufLocation.latitude = Int32(location.coordinate.latitude * 1e7)
        protobufLocation.longitude = Int32(location.coordinate.longitude * 1e7)
        protobufLocation.altitude = Int32(location.altitude)

        let serializedLocation = try protobufLocation.serializedData()
        let encryptedLocation = try LocationCryptor.encryptSymmetric(identityKey: identityKey, reportBytes: serializedLocation)

        report.location.geoLocation.encryptedReport.encryptedLocation = encryptedLocation
        report.location.geoLocation.encryptedReport.isOwnReport = true
        report.location.geoLocation.lastAggregatedAccuracy = Float(location.horizontalAccuracy)
        report.advertisement.identifier.canonicDeviceID = CanonicIdToBytes.convert(canonicDeviceId)

        var ownerReport = LocationReportsUpload()
        ownerReport.reports.append(report)
        ownerReport.clientMetadata.version.playServicesVersion = "24.36.33 (100300-{{cl}})"

        return ownerReport
    }
}
