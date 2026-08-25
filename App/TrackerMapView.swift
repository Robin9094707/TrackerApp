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
                        Annotation(tracker.name, coordinate: location.coordinate) {
                            Button { selected = tracker; Haptics.impact() } label: {
                                ZStack { Circle().fill(.background).frame(width: 48, height: 48).shadow(radius: 5); Text(tracker.emoji ?? "📍").font(.title2) }
                            }.buttonStyle(.plain).accessibilityLabel("\(tracker.name), \(tracker.provider)")
                        }
                    }
                }
                ForEach(model.bootstrap?.geofences ?? []) { fence in
                    MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100).foregroundStyle(.tint.opacity(0.12))
                }
            }.mapStyle(.standard(elevation: .realistic)).mapControls { MapCompass(); MapScaleView() }.ignoresSafeArea(edges: .bottom)

            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(selected.emoji ?? "📍").font(.title2); Text(selected.name).font(.headline); Spacer(); ProviderBadge(provider: selected.provider) }
                    if let location = selected.location { Text(location.address?.bestText.isEmpty == false ? location.address!.bestText : "\(location.latitude), \(location.longitude)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    HStack {
                        NavigationLink(value: selected) { Label("Details", systemImage: "info.circle") }.buttonStyle(.borderedProminent)
                        Button { Task { await model.locate(selected) } } label: { Label("Orten", systemImage: "location.fill") }.buttonStyle(.bordered)
                    }
                }.padding(16).rjGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding()
            }
        }
        .navigationTitle("Karte").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Tracker.self) { TrackerDetailView(tracker: $0) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { position = .automatic } label: { Image(systemName: "scope") } } }
    }
}
