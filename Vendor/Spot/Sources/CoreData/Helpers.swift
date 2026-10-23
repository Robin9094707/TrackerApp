//
//  Helpers.swift
//  Spot
//
//  Created by Leon Böttger on 06.01.25.
//

import CoreData
import Foundation
import LUI

func loadReportsFromDisk(for canonicDeviceId: String) -> [RefreshWrapper] {
    PersistenceController.shared.getDatabaseQueue().sync {
        let context = PersistenceController.shared.container.newBackgroundContext()
        var resultArray = [RefreshWrapper]()

        if let device = fetchDeviceForCanonicDeviceID(canonicDeviceId, context: context) {
            var lastDate = Date.distantPast

            for refresh in Array(device.refreshes as? Set<StoredRefresh> ?? []).sorted(by: { $0.date! < $1.date! }) {
                var refreshArray = [LocationReportWrapper]()

                let reports = Array(refresh.reports as? Set<StoredLocationReport> ?? []).sorted(by: { $0.time! > $1.time! })

                for report in reports {
                    if let status = LocationReport.Status(rawValue: Int(report.status)), let time = report.time {
                        let report = LocationReportWrapper(decryptedLocation: DecryptedLocation(latitude: report.latitude, longitude: report.longitude, altitude: report.altitude), time: time, accuracy: report.accuracy, status: status, isOwnReport: report.isOwnReport)

                        refreshArray.append(report)
                    }
                }

                var wrapper = RefreshWrapper(time: refresh.date!, contributorType: ContributorType.fromInt(Int(refresh.contributorType)), reports: refreshArray)

                if let first = refreshArray.first, first.time > lastDate {
                    lastDate = first.time
                    wrapper.hasNewReport = true
                }

                resultArray.insert(wrapper, at: 0)
            }
        }

        return resultArray
    }
}

func storeReportsOnDisk(requestDate: Date, contributorType: ContributorType, canonicDeviceId: String, decryptedRefresh: RefreshWrapper) {
    PersistenceController.shared.modifyDatabaseBackground { context in
        var device: StoredDevice

        if let existingDevice = fetchDeviceForCanonicDeviceID(canonicDeviceId, context: context) {
            // Device already exists
            device = existingDevice
        } else {
            // Create new device
            device = StoredDevice(context: context)
            device.canonicDeviceId = canonicDeviceId
        }

        let newRefresh = StoredRefresh(context: context)
        newRefresh.date = requestDate
        newRefresh.contributorType = Int16(contributorType.toInt())

        let refreshes = Array(device.refreshes as? Set<StoredRefresh> ?? [])
        let existingReports: Set<StoredLocationReport> = Set(refreshes.flatMap { $0.reports as? Set<StoredLocationReport> ?? [] })

        for report in decryptedRefresh.reports {
            // check if report already stored
            if let latitude = report.decryptedLocation?.latitude, let longitude = report.decryptedLocation?.longitude, let altitude = report.decryptedLocation?.altitude, let accuracy = report.accuracy {
                var newDbRecord: StoredLocationReport

                if let existingReport = existingReports.first(where: { $0.time == report.time && $0.latitude == latitude && $0.longitude == longitude && $0.altitude == altitude }) {
                    newDbRecord = existingReport
                } else {
                    let newReport = StoredLocationReport(context: context)
                    newReport.latitude = latitude
                    newReport.longitude = longitude
                    newReport.altitude = altitude
                    newReport.status = Int16(report.status.rawValue)
                    newReport.time = report.time
                    newReport.accuracy = accuracy
                    newReport.isOwnReport = report.isOwnReport
                    newDbRecord = newReport
                }

                newRefresh.addToReports(newDbRecord)
            }
        }

        device.addToRefreshes(newRefresh)
    }
}

private func fetchDeviceForCanonicDeviceID(_ canonicDeviceId: String, context: NSManagedObjectContext) -> StoredDevice? {
    if let existingDevice = fetchDevices(withPredicate: NSPredicate(format: "canonicDeviceId == %@", canonicDeviceId), withLimit: 1, context: context).first {
        return existingDevice
    }

    return nil
}

/// Fetches all devices meeting the predicate. Limit of array can be specified in `withLimit`.
private func fetchDevices(withPredicate: NSPredicate? = nil, withLimit: Int? = nil, context: NSManagedObjectContext) -> [StoredDevice] {
    // create fetch request
    let fetchRequest: NSFetchRequest<StoredDevice>
    fetchRequest = StoredDevice.fetchRequest()

    // set limit
    if let withLimit {
        fetchRequest.fetchLimit = withLimit
    }

    // set predicate
    fetchRequest.predicate = withPredicate

    // try to fetch
    do {
        return try context.fetch(fetchRequest)
    }

    // error occured
    catch {}

    // default: nothing to return
    return []
}

enum ContributorType: String, Codable, CaseIterable {
    case AtAllAreas
    case HighTrafficOnly
    case Adaptive

    func toInt() -> Int {
        switch self {
        case .AtAllAreas: 1
        case .HighTrafficOnly: 2
        case .Adaptive: 3
        }
    }

    static func fromInt(_ value: Int) -> ContributorType {
        switch value {
        case 1: .AtAllAreas
        case 2: .HighTrafficOnly
        case 3: .Adaptive
        default:
            .AtAllAreas
        }
    }

    func toString() -> String {
        switch self {
        case .AtAllAreas: "At All Areas"
        case .HighTrafficOnly: "High Traffic Only"
        case .Adaptive: "Adaptive"
        }
    }
}

struct CachedToken {
    let token: String
    let expirationDate: Date
}

extension Date {
    var isInPast: Bool {
        self < Date()
    }
}
