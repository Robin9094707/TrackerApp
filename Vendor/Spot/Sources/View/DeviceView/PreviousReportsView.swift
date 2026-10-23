//
//  PreviousReportsView.swift
//  Spot
//
//  Created by Leon Böttger on 28.01.25.
//

import LUI
import SwiftUI

struct PreviousReportsView: View {
    @ObservedObject var device: LocalFindMyDevice
    @State var filterNew = true

    var body: some View {
        let refreshes = device.refreshes.filter { !filterNew || $0.hasNewReport }

        NavigationSubView(header: "History") {
            CustomSection {
                Toggle(isOn: $filterNew.animation(.smooth)) {
                    SettingsLabel(imageName: "star.fill", text: "Only Show Reports With New Data", backgroundColor: .green)
                }
            }

            LazyVStack {
                CustomSection(header: "All Reports") {
                    if refreshes.isEmpty {
                        SettingsLabel(imageName: "info", text: "No Reports Found", backgroundColor: .red)
                    } else {
                        ForEach(refreshes) { refresh in
                            LUILink(destination: NavigationSubView(header: "Reports") {
                                CustomSection {
                                    CustomPickerLabel(selection: refresh.contributorType.toString(), backgroundColor: .blue, description: "Contributor Type", imageName: "person.wave.2.fill", isLink: false)
                                }

                                LocationsSection(device: device, reports: refresh.reports, showLocationHistoryLink: false)
                            }) {
                                CustomPickerLabel(selection: (refresh.hasNewReport ? "New - " : "") + refresh.reports.count.description, backgroundColor: .blue, description: dateToStaticString(refresh.time, currentDate: Date()), imageName: "clock.arrow.trianglehead.counterclockwise.rotate.90", isLink: true)
                            }
                        }
                    }
                }
            }

            CustomSection(header: "Advanced") {
                ShareButton(label: "Export as CSV") {
                    generateCSV()
                }
            }
        }
    }

    func generateCSV() -> String {
        // CSV Header
        var csvText = "latitude,longitude,accuracy,timestamp,publishTimestamp\n"

        let annotations = getMapAnnotations(refreshes: device.refreshes)

        for entry in annotations.sorted(by: { $0.date < $1.date }) {
            let latitude = entry.location.latitude
            let longitude = entry.location.longitude
            let timestamp = entry.date.unixTime
            let accuracy = entry.accuracy
            let publishDate = entry.publishDate.unixTime

            let row = "\(latitude),\(longitude),\(accuracy),\(timestamp),\(publishDate)\n"
            csvText.append(row)
        }

        return csvText
    }
}
