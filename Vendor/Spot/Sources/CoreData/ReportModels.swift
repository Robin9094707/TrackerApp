//
//  LocationReportWrapper.swift
//  Spot
//
//  Created by Leon Böttger on 26.12.24.
//

import Foundation

struct RefreshWrapper: Identifiable, Equatable {
    var id = UUID()

    let time: Date
    let contributorType: ContributorType
    var reports: [LocationReportWrapper]

    var hasNewReport = false
}

struct LocationReportWrapper: Identifiable, Equatable {
    static func == (lhs: LocationReportWrapper, rhs: LocationReportWrapper) -> Bool {
        lhs.time == rhs.time && lhs.status == rhs.status && lhs.encryptedLocation == rhs.encryptedLocation && lhs.decryptedLocation == rhs.decryptedLocation && lhs.isOwnReport == rhs.isOwnReport && lhs.accuracy == rhs.accuracy && lhs.name == rhs.name
    }

    var time: Date
    var status: LocationReport.Status
    var decryptedLocation: DecryptedLocation?
    var encryptedLocation: LocationReport.GeoLocation?
    var isOwnReport: Bool
    var accuracy: Float?
    var name: String?

    let id = UUID()

    init(encryptedLocation: LocationReport.GeoLocation, time: Date, accuracy: Float, status: LocationReport.Status, isOwnReport: Bool) {
        self.time = time
        self.status = status
        self.encryptedLocation = encryptedLocation
        self.isOwnReport = isOwnReport
        self.accuracy = accuracy
    }

    init(decryptedLocation: DecryptedLocation, time: Date, accuracy: Float, status: LocationReport.Status, isOwnReport: Bool) {
        self.time = time
        self.status = status
        self.decryptedLocation = decryptedLocation
        self.isOwnReport = isOwnReport
        self.accuracy = accuracy
        encryptedLocation = LocationReport.GeoLocation()
    }

    init(time: Date, name: String) {
        self.time = time
        status = .semantic
        isOwnReport = true
        self.name = name
    }
}
