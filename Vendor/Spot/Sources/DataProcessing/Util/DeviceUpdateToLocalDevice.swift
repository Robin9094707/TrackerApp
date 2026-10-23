//
//  DeviceUpdateToLocalDevice.swift
//  Spot
//
//  Created by Leon Böttger on 26.12.24.
//

import Foundation
import SwiftUI

func mergeDeviceUpdate(requestDate: Date, contributorType: ContributorType, deviceUpdateProtobuf: DeviceUpdate, localDevice: LocalFindMyDevice) -> Bool {
    guard localDevice.belongsToCurrentAccount else { return false }
    // also update keys if necessary
    let _ = convertToLocalFindMyDevice(deviceMetadata: deviceUpdateProtobuf.deviceMetadata, existingDevices: [localDevice])

    DispatchQueue.main.async {
        localDevice.lastReportRefresh = .now
    }

    var newReports = [LocationReportWrapper]()

    let information = getInformation(deviceMetadata: deviceUpdateProtobuf.deviceMetadata)
    let protoReports = information.locationInformation.reports

    var networkLocations = protoReports.recentLocationAndNetworkLocations.networkLocations
    var networkLocationsTime = protoReports.recentLocationAndNetworkLocations.networkLocationTimestamps

    if protoReports.recentLocationAndNetworkLocations.hasRecentLocation {
        let recentLocation = protoReports.recentLocationAndNetworkLocations.recentLocation
        let recentLocationTime = protoReports.recentLocationAndNetworkLocations.recentLocationTimestamp

        networkLocations.append(recentLocation)
        networkLocationsTime.append(recentLocationTime)
    }

    newReports = zip(networkLocations, networkLocationsTime).map { encryptedLocationInfo, time in
        let encryptedLocation = encryptedLocationInfo.geoLocation
        let time = unixTimeToDate(unixTime: time.seconds)
        let accuracy = encryptedLocationInfo.geoLocation.lastAggregatedAccuracy
        let status = encryptedLocationInfo.status
        let isOwnReport = encryptedLocationInfo.geoLocation.encryptedReport.isOwnReport

        if encryptedLocationInfo.hasSemanticLocation {
            return LocationReportWrapper(time: time, name: encryptedLocationInfo.semanticLocation.locationName)
        } else {
            return LocationReportWrapper(encryptedLocation: encryptedLocation, time: time, accuracy: accuracy, status: status, isOwnReport: isOwnReport)
        }
    }

    newReports.sort(by: { $0.time > $1.time })

    let previousLastReport = localDevice.refreshes.first?.reports.first?.time
    let receivedUpdate = (previousLastReport == nil && !newReports.isEmpty) || (newReports.first?.time ?? Date.distantPast > previousLastReport ?? Date.distantPast)

    let alreadyHasEnoughHighTrafficReports = localDevice.refreshes.first?.reports.filter { $0.status == .aggregated }.count ?? 0 >= 2

    DispatchQueue.main.async {
        guard localDevice.belongsToCurrentAccount else { return }
        withAnimation(.spring) {
            var newRefresh = RefreshWrapper(time: requestDate, contributorType: contributorType, reports: newReports)
            newRefresh.hasNewReport = receivedUpdate
            localDevice.refreshes.insert(newRefresh, at: 0)

            LocationCryptor.decryptList(device: localDevice, refresh: newRefresh) { decryptedRefresh in
                guard localDevice.belongsToCurrentAccount else { return }
                storeReportsOnDisk(requestDate: requestDate, contributorType: contributorType, canonicDeviceId: localDevice.canonicDeviceId, decryptedRefresh: decryptedRefresh)
            }
        }
    }

    return receivedUpdate || alreadyHasEnoughHighTrafficReports
}
