//
//  DetailLocationView.swift
//  Spot
//
//  Created by Leon Böttger on 11.12.24.
//

import LUI
import SwiftUI

public struct DetailLocationView: View {
    let report: LocationReportWrapper

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        NavigationSubView(header: "Location Info") {
            if report.status != .semantic {
                CustomSection {
                    CustomPickerLabel(selection: report.decryptedLocation?.latitude.description ?? "Encrypted", backgroundColor: .blue, description: "Latitude", imageName: "mappin", isLink: false)

                    CustomPickerLabel(selection: report.decryptedLocation?.longitude.description ?? "Encrypted", backgroundColor: .blue, description: "Longitude", imageName: "mappin", isLink: false)

                    CustomPickerLabel(selection: report.decryptedLocation?.altitude.description ?? "Encrypted", backgroundColor: .green, description: "Altitude", imageName: "arrow.up.arrow.down", isLink: false)

                    CustomPickerLabel(selection: (report.accuracy?.description ?? "-") + " m", backgroundColor: .yellow, description: "Accuracy", imageName: "mappin.and.ellipse", isLink: false)
                }
            }

            CustomSection {
                CustomPickerLabel(selection: dateToString(report.time, withSeconds: true), backgroundColor: .blue, description: "Time", imageName: "clock.fill", isLink: false)

                let status = statusToString(report.status, semanticLocation: report.name, colorScheme: colorScheme)

                CustomPickerLabel(selection: status.label, backgroundColor: .green, description: "Status", imageName: status.icon, isLink: false)

                CustomPickerLabel(selection: report.isOwnReport.description, backgroundColor: .orange, description: "Own Report", imageName: "person.fill", isLink: false)
            }
        }
    }
}
