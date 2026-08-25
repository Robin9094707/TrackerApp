import SwiftUI
import MapKit

struct TrackerMapView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Tracker?
    @State private var position: MapCameraPosition = .automatic

    private var located: [Tracker] { model.filteredTrackers.filter { $0.location != nil } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(located) { tracker in
                    if let location = tracker.location {
                        if selected?.ref == tracker.ref, let accuracy = location.accuracyM, accuracy > 0 {
                            MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                                .foregroundStyle(Color.accentColor.opacity(0.13))
                                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                        }
                        Annotation(tracker.name, coordinate: location.coordinate) {
                            Button { select(tracker) } label: {
                                ZStack {
                                    Circle().fill(.background).frame(width: 48, height: 48).shadow(radius: 5)
                                    if model.isLocating(tracker) { ProgressView().controlSize(.small) }
                                    else { Text(tracker.emoji ?? "📍").font(.title2) }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(tracker.name), \(tracker.provider)")
                        }
                    }
                }
                ForEach(model.bootstrap?.geofences ?? []) { fence in
                    MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100)
                        .foregroundStyle(.tint.opacity(0.08))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
            .ignoresSafeArea(edges: .bottom)

            if let selected {
                selectedCard(selected)
                    .padding()
            }
        }
        .navigationTitle("Karte")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Tracker.self) { TrackerDetailView(tracker: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { position = .automatic } label: { Image(systemName: "scope") }
            }
        }
    }

    private func selectedCard(_ tracker: Tracker) -> some View {
        let current = model.trackers.first(where: { $0.ref == tracker.ref }) ?? tracker
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(current.emoji ?? "📍").font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.name).font(.headline)
                    FreshnessLabel(timestamp: current.location?.timestamp ?? current.lastSeenTs)
                }
                Spacer()
                AccuracyPill(accuracy: current.location?.accuracyM)
            }

            if let location = current.location {
                Text(location.address?.bestText.isEmpty == false ? location.address!.bestText : "\(location.latitude), \(location.longitude)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button { Task { await model.locate(current) } } label: {
                    if model.isLocating(current) {
                        HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Ortung läuft …") }
                    } else {
                        Label("Orten", systemImage: "location.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLocating(current))

                NavigationLink(value: current) { Label("Details", systemImage: "info.circle") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .rjGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func select(_ tracker: Tracker) {
        selected = tracker
        Haptics.impact()
        if let location = tracker.location {
            let accuracy = max(location.accuracyM ?? 80, 80)
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: max(700, accuracy * 6),
                longitudinalMeters: max(700, accuracy * 6)
            ))
        }
    }
}
