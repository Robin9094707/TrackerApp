//
//  DetailMapView.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import CoreData
import CoreLocation
import LUI
import SwiftUI

struct DetailMapView: View {
    @Binding var detailMapShown: Bool
    let refreshes: [RefreshWrapper]
    @State var smallMapFinishedLoading = false
    @ObservedObject var tokenManager = TokenManager.sharedInstance

    var body: some View {
        let annotations = tokenManager.ownerKey == nil ? [] : getMapAnnotations(refreshes: refreshes).map { MapAnnotation(mapLocation: $0) }

        ZStack {
            if let first = annotations.first {
                ZStack {
                    CustomSection {
                        LUILink(destination: NavigationSubView(header: "Tracker Locations", navigationBarLayout: .SmallOnlyAlways, supportsScrolling: false) {
                            StaticMapView(annotations: annotations)
                        }
                        .ignoresSafeArea(.all, edges: [.horizontal, .vertical])
                        .background(LoadingIndicator().frame(width: 20)),

                        isActive: $detailMapShown, label: {
                            MapView(annotations: [first], showRadii: true, connections: [], mapFinishedLoading: $smallMapFinishedLoading)
                                .overlay(
                                    ZStack {
                                        VStack {
                                            HStack {
                                                Spacer()

                                                ZStack {
                                                    Blur(style: .systemUltraThinMaterialDark)
                                                        .cornerRadius(10)
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .foregroundColor(.white)
                                                }

                                                .frame(width: 30, height: 30, alignment: .center)
                                                .padding()
                                            }

                                            Spacer()
                                        }
                                    }
                                )

                                .background(LoadingIndicator().frame(width: 20))
                                .allowsHitTesting(false)
                                .compositingGroup()
                                .contentShape(Rectangle())
                                .cornerRadius(22)
                                .padding(.horizontal, -15)
                        })
                        .padding(1)
                    }
                    .animation(.easeInOut, value: !smallMapFinishedLoading)
                }
            }

            else {
                MapPlaceholderView()
            }
        }
        .frame(height: 200)
    }
}

struct StaticMapView: View {
    @State var annotations: [MapAnnotation]

    var body: some View {
        MapView(annotations: annotations, showRadii: false, connections: [], mapFinishedLoading: .constant(true))
    }
}

func getMapAnnotations(refreshes: [RefreshWrapper]) -> [MapLocation] {
    var annotations: [MapLocation] = []

    for refresh in refreshes {
        for report in refresh.reports {
            if let decryptedLocation = report.decryptedLocation, let accuracy = report.accuracy, !annotations.contains(where: { $0.location.latitude == decryptedLocation.latitude && $0.location.longitude == decryptedLocation.longitude }) {
                let annotation = MapLocation(location: CLLocationCoordinate2D(latitude: decryptedLocation.latitude, longitude: decryptedLocation.longitude), date: report.time, accuracy: Double(accuracy), publishDate: refresh.time)
                annotations.append(annotation)
            }
        }
    }

    return annotations
}

struct MapPlaceholderView: View {
    var body: some View {
        CustomSection {
            VStack {
                Spacer()

                Image(systemName: "map.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                    .padding(.bottom, 5)

                HStack {
                    Spacer()

                    LUIText("The map is unavailable because no locations were found.", isBold: true, centered: true)
                        .opacity(0.5)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }

                Spacer()
            }
        }
        .frame(height: 190)
    }
}

/// Struct to store data of the locations shown on the map
struct MapLocation {
    let location: CLLocationCoordinate2D
    let date: Date
    var accuracy: Double
    let publishDate: Date
}
